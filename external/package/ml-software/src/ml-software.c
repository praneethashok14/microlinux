/*
 * ml-software - MicroLinux Software: a graphical front end for mlpkg
 *
 *   ml-software [SEARCH]
 *   ml-software --install FILE...    (opening a .deb, .rpm or .mlp in the file manager)
 *
 * Reads the package lists that "mlpkg update" downloaded (/var/cache/mlpkg:
 * INDEX.n, CATEGORIES.n) and the installed packages (/var/lib/mlpkg/installed),
 * and runs mlpkg through "sudo -A" (password dialog: ml-askpass) to refresh the
 * lists, install, remove and upgrade. mlpkg does all the work; its output is
 * shown live at the bottom of the window. "Install .deb/.rpm/.mlp..." install
 * package files with ml-file-install: Debian / Ubuntu packages as deb-NAME,
 * RHEL / AlmaLinux / Fedora packages as rpm-NAME, MicroLinux packages as they are.
 */
#include <gtk/gtk.h>
#include <string.h>

#define CACHE "/var/cache/mlpkg"
#define LIB "/var/lib/mlpkg/installed"
#define RUN "/run/mlpkg/active"
#define ASKPASS "/usr/libexec/ml-askpass"
#define FILE_INSTALL "/usr/libexec/ml-file-install"
#define DEB_CATEGORY "From .deb files"
#define RPM_CATEGORY "From .rpm files"
#define MLP_CATEGORY "From .mlp files"

typedef struct {
	char *name, *version, *size, *desc, *deps, *section, *category;
	char *installed;   /* installed version, or NULL */
	gboolean live;     /* active from the live medium */
	gboolean autodep;  /* installed as a dependency */
} Pkg;

static GPtrArray *pkgs;
static GtkWidget *window, *cat_list, *pkg_list, *search, *status, *spinner, *log_view, *log_revealer,
	*update_all, *libs_check, *placeholder, *details_btn;
static char *current_cat;   /* "All", "Installed", "Updates" or a category */
static gboolean busy;

static void reload(void);

/* ------------------------------------------------------------------------ */
/* data                                                                     */
/* ------------------------------------------------------------------------ */

static void pkg_free(gpointer p)
{
	Pkg *k = p;
	g_free(k->name); g_free(k->version); g_free(k->size); g_free(k->desc);
	g_free(k->deps); g_free(k->section); g_free(k->category); g_free(k->installed);
	g_free(k);
}

static char *info_get(const char *path, const char *key)
{
	char *text = NULL, *v = NULL;
	if (!g_file_get_contents(path, &text, NULL, NULL))
		return NULL;
	char **lines = g_strsplit(text, "\n", -1);
	size_t kl = strlen(key);
	for (char **l = lines; *l && !v; l++)
		if (strncmp(*l, key, kl) == 0 && (*l)[kl] == '=')
			v = g_strdup(*l + kl + 1);
	g_strfreev(lines);
	g_free(text);
	return v;
}

static gboolean has_update(const Pkg *k)
{
	return k->installed && g_strcmp0(k->installed, k->version) != 0;
}

static void load_data(void)
{
	if (pkgs)
		g_ptr_array_free(pkgs, TRUE);
	pkgs = g_ptr_array_new_with_free_func(pkg_free);
	GHashTable *seen = g_hash_table_new(g_str_hash, g_str_equal);
	GHashTable *cats = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
	GDir *d = g_dir_open(CACHE, 0, NULL);
	const char *n;
	GPtrArray *indexes = g_ptr_array_new_with_free_func(g_free);
	while (d && (n = g_dir_read_name(d))) {
		char *p = g_build_filename(CACHE, n, NULL), *text = NULL;
		if (g_str_has_prefix(n, "CATEGORIES.") && g_file_get_contents(p, &text, NULL, NULL)) {
			char **lines = g_strsplit(text, "\n", -1);
			for (char **l = lines; *l; l++) {
				char *bar = strchr(*l, '|');
				if (bar && !g_hash_table_contains(cats, *l))
					g_hash_table_insert(cats, g_strndup(*l, bar - *l), g_strdup(bar + 1));
			}
			g_strfreev(lines);
		} else if (g_str_has_prefix(n, "INDEX.")) {
			g_ptr_array_add(indexes, g_strdup(p));
		}
		g_free(text);
		g_free(p);
	}
	if (d)
		g_dir_close(d);
	g_ptr_array_sort(indexes, (GCompareFunc)g_strcmp0);   /* INDEX.1 (first repository) wins */
	for (guint i = 0; i < indexes->len; i++) {
		char *text = NULL;
		if (!g_file_get_contents(indexes->pdata[i], &text, NULL, NULL))
			continue;
		char **lines = g_strsplit(text, "\n", -1);
		for (char **l = lines; *l; l++) {
			char **f = g_strsplit(*l, "|", 9);
			if (g_strv_length(f) >= 6 && !g_hash_table_contains(seen, f[0])) {
				Pkg *k = g_new0(Pkg, 1);
				k->name = g_strdup(f[0]);
				k->version = g_strdup(f[1]);
				double mb = g_ascii_strtod(f[4], NULL) / 1048576.0;
				k->size = mb >= 1 ? g_strdup_printf("%.0f MB", mb) : g_strdup_printf("%.0f KB", mb * 1024 + 0.5);
				k->desc = g_strdup(f[5]);
				k->deps = g_strdup(f[6] ? f[6] : "");
				k->section = g_strdup(f[6] && f[7] ? f[7] : "app");
				const char *c = g_hash_table_lookup(cats, f[0]);
				k->category = g_strdup(c ? c : (g_strcmp0(k->section, "lib") == 0 ? "Libraries" : "Other"));
				char *inf = g_strdup_printf(LIB "/%s.info", k->name), *act = g_strdup_printf(RUN "/%s", k->name);
				if (g_file_test(inf, G_FILE_TEST_EXISTS)) {
					k->installed = info_get(inf, "version");
					char *a = info_get(inf, "auto");
					k->autodep = g_strcmp0(a, "1") == 0;
					g_free(a);
				}
				k->live = !k->installed && g_file_test(act, G_FILE_TEST_EXISTS);
				g_free(inf);
				g_free(act);
				g_hash_table_add(seen, k->name);
				g_ptr_array_add(pkgs, k);
			}
			g_strfreev(f);
		}
		g_strfreev(lines);
		g_free(text);
	}
	g_ptr_array_free(indexes, TRUE);
	/* installed packages no repository has (made from .deb files) */
	d = g_dir_open(LIB, 0, NULL);
	while (d && (n = g_dir_read_name(d))) {
		if (!g_str_has_suffix(n, ".info"))
			continue;
		char *name = g_strndup(n, strlen(n) - 5), *inf = g_build_filename(LIB, n, NULL);
		if (g_hash_table_contains(seen, name)) {
			g_free(name);
			g_free(inf);
			continue;
		}
		char *origin = info_get(inf, "origin"), *desc = info_get(inf, "description");
		Pkg *k = g_new0(Pkg, 1);
		k->name = name;
		k->installed = info_get(inf, "version");
		k->version = g_strdup(k->installed ? k->installed : "");
		k->size = g_strdup("");
		k->desc = desc ? desc : g_strdup("");
		k->deps = g_strdup("");
		k->section = g_strdup("app");
		k->category = g_strdup(g_strcmp0(origin, "deb") == 0   ? DEB_CATEGORY
		                       : g_strcmp0(origin, "rpm") == 0 ? RPM_CATEGORY
		                                                       : MLP_CATEGORY);
		g_free(origin);
		g_free(inf);
		g_hash_table_add(seen, k->name);
		g_ptr_array_add(pkgs, k);
	}
	if (d)
		g_dir_close(d);
	g_hash_table_destroy(seen);
	g_hash_table_destroy(cats);
}

/* ------------------------------------------------------------------------ */
/* running mlpkg                                                            */
/* ------------------------------------------------------------------------ */

static void log_append(const char *line)
{
	GtkTextBuffer *b = gtk_text_view_get_buffer(GTK_TEXT_VIEW(log_view));
	GtkTextIter end;
	gtk_text_buffer_get_end_iter(b, &end);
	gtk_text_buffer_insert(b, &end, line, -1);
	gtk_text_buffer_insert(b, &end, "\n", 1);
	gtk_text_buffer_get_end_iter(b, &end);
	GtkTextMark *m = gtk_text_buffer_create_mark(b, NULL, &end, FALSE);
	gtk_text_view_scroll_mark_onscreen(GTK_TEXT_VIEW(log_view), m);
	gtk_text_buffer_delete_mark(b, m);
}

static void set_busy(gboolean b, const char *what)
{
	busy = b;
	gtk_label_set_text(GTK_LABEL(status), what);
	if (b)
		gtk_spinner_start(GTK_SPINNER(spinner));
	else
		gtk_spinner_stop(GTK_SPINNER(spinner));
	gtk_widget_set_sensitive(pkg_list, !b);
	gtk_widget_set_sensitive(update_all, !b);
}

static void read_line(GObject *src, GAsyncResult *res, gpointer data)
{
	char *line = g_data_input_stream_read_line_finish_utf8(G_DATA_INPUT_STREAM(src), res, NULL, NULL);
	if (!line) {
		g_object_unref(src);
		return;
	}
	log_append(line);
	gtk_label_set_text(GTK_LABEL(status), line);
	g_free(line);
	g_data_input_stream_read_line_async(G_DATA_INPUT_STREAM(src), G_PRIORITY_DEFAULT, NULL, read_line, NULL);
}

static void finished(GObject *src, GAsyncResult *res, gpointer data)
{
	char *what = data;
	gboolean ok = g_subprocess_wait_check_finish(G_SUBPROCESS(src), res, NULL);
	set_busy(FALSE, "");
	char *msg = g_strdup_printf("%s: %s", what, ok ? "done" : "failed (see the details below)");
	gtk_label_set_text(GTK_LABEL(status), msg);
	if (!ok)
		gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(details_btn), TRUE);   /* shows mlpkg's output */
	g_free(msg);
	g_free(what);
	g_object_unref(src);
	reload();
}

/* sudo -A PROG ARGS...; WHAT describes it for the status line */
static void run_root(const char *what, const char *prog, const char *const *args)
{
	if (busy)
		return;
	GPtrArray *a = g_ptr_array_new();
	g_ptr_array_add(a, "sudo");
	g_ptr_array_add(a, "-A");
	g_ptr_array_add(a, (gpointer)prog);
	for (int i = 0; args[i]; i++)
		g_ptr_array_add(a, (gpointer)args[i]);
	g_ptr_array_add(a, NULL);
	GSubprocessLauncher *l = g_subprocess_launcher_new(G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_MERGE);
	g_subprocess_launcher_setenv(l, "SUDO_ASKPASS", ASKPASS, TRUE);
	g_subprocess_launcher_setenv(l, "LC_ALL", "C", TRUE);
	GError *e = NULL;
	GSubprocess *p = g_subprocess_launcher_spawnv(l, (const char *const *)a->pdata, &e);
	g_object_unref(l);
	g_ptr_array_free(a, TRUE);
	if (!p) {
		gtk_label_set_text(GTK_LABEL(status), e->message);
		g_error_free(e);
		return;
	}
	char *head = g_strdup_printf("--- %s", what);
	log_append(head);
	g_free(head);
	set_busy(TRUE, what);
	GDataInputStream *in = g_data_input_stream_new(g_subprocess_get_stdout_pipe(p));
	g_data_input_stream_read_line_async(in, G_PRIORITY_DEFAULT, NULL, read_line, NULL);
	g_subprocess_wait_check_async(p, NULL, finished, g_strdup(what));
}

static void mlpkg(const char *what, const char *const *args)
{
	run_root(what, "mlpkg", args);
}

/* category for package files of this name (.deb, .rpm, .mlp) */
static const char *file_category(const char *path)
{
	return g_str_has_suffix(path, ".deb") ? DEB_CATEGORY : g_str_has_suffix(path, ".rpm") ? RPM_CATEGORY : MLP_CATEGORY;
}

/* install package files (a NULL-terminated list of absolute paths), after
 * asking: a package file can change anything on the system */
static void install_files(char **files)
{
	if (busy || !files || !files[0])
		return;
	guint n = g_strv_length(files);
	char *base = g_path_get_basename(files[0]);
	char *title = n > 1 ? g_strdup_printf("Install %u packages?", n) : g_strdup_printf("Install “%s”?", base);
	GtkWidget *q = gtk_message_dialog_new(GTK_WINDOW(window), GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION, GTK_BUTTONS_NONE,
	                                      "%s", title);
	g_free(title);
	gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(q),
		"Install only packages from sources you trust: a package can change anything on this computer. "
		"Packages made for Debian/Ubuntu or RHEL/AlmaLinux/Fedora run with those systems' libraries when they need them.");
	gtk_dialog_add_buttons(GTK_DIALOG(q), "_Cancel", GTK_RESPONSE_CANCEL, "_Install", GTK_RESPONSE_OK, NULL);
	int r = gtk_dialog_run(GTK_DIALOG(q));
	gtk_widget_destroy(q);
	if (r == GTK_RESPONSE_OK) {
		char *what = n > 1 ? g_strdup_printf("Installing %u packages", n) : g_strdup_printf("Installing %s", base);
		gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(details_btn), TRUE);   /* what it installs, what it needs */
		g_free(current_cat);
		current_cat = g_strdup(file_category(files[0]));
		run_root(what, FILE_INSTALL, (const char *const *)files);
		g_free(what);
	}
	g_free(base);
}

/* "Install .deb...", "Install .rpm...", "Install .mlp...": DATA is the extension */
static void on_install_file(GtkButton *b, gpointer data)
{
	const char *ext = data;
	static const char *const kinds[][3] = {
		{"deb", "Debian / Ubuntu packages (.deb)", "application/vnd.debian.binary-package"},
		{"rpm", "RHEL / AlmaLinux / Rocky / Fedora packages (.rpm)", "application/x-rpm"},
		{"mlp", "MicroLinux packages (.mlp)", "application/x-microlinux-package"}};
	if (busy)
		return;
	char *title = g_strdup_printf("Install .%s packages", ext);
	GtkFileChooserNative *c = gtk_file_chooser_native_new(title, GTK_WINDOW(window), GTK_FILE_CHOOSER_ACTION_OPEN,
	                                                      "_Install", "_Cancel");
	g_free(title);
	GtkFileFilter *f = gtk_file_filter_new();
	for (size_t i = 0; i < G_N_ELEMENTS(kinds); i++)
		if (strcmp(kinds[i][0], ext) == 0) {
			char *pat = g_strdup_printf("*.%s", ext);
			gtk_file_filter_set_name(f, kinds[i][1]);
			gtk_file_filter_add_pattern(f, pat);
			gtk_file_filter_add_mime_type(f, kinds[i][2]);
			g_free(pat);
		}
	gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(c), f);
	gtk_file_chooser_set_select_multiple(GTK_FILE_CHOOSER(c), TRUE);
	char *dl = g_build_filename(g_get_home_dir(), "Downloads", NULL);
	if (g_file_test(dl, G_FILE_TEST_IS_DIR))
		gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(c), dl);
	g_free(dl);
	if (gtk_native_dialog_run(GTK_NATIVE_DIALOG(c)) == GTK_RESPONSE_ACCEPT) {
		GSList *l = gtk_file_chooser_get_filenames(GTK_FILE_CHOOSER(c));
		GPtrArray *a = g_ptr_array_new_with_free_func(g_free);
		for (GSList *i = l; i; i = i->next)
			g_ptr_array_add(a, i->data);
		g_slist_free(l);
		g_ptr_array_add(a, NULL);
		install_files((char **)a->pdata);
		g_ptr_array_free(a, TRUE);
	}
	g_object_unref(c);
}

/* ------------------------------------------------------------------------ */
/* package rows                                                             */
/* ------------------------------------------------------------------------ */

static const char *cat_icon(const char *cat)
{
	static const char *const map[][2] = {
		{"Development", "applications-development"}, {"Editors", "accessories-text-editor"},
		{"Command line", "utilities-terminal"},     {"Internet & network", "applications-internet"},
		{"Disks", "drive-harddisk"},                {"Desktop & media", "applications-multimedia"},
		{"Games", "applications-games"},            {"System", "applications-system"},
		{DEB_CATEGORY, "application-x-deb"},        {RPM_CATEGORY, "application-x-rpm"},
		{MLP_CATEGORY, "package-x-generic"},
		{"Installed", "emblem-ok-symbolic"},        {"Updates", "software-update-available"},
		{"All", "view-app-grid-symbolic"},          {NULL, NULL}};
	for (int i = 0; map[i][0]; i++)
		if (strcmp(map[i][0], cat) == 0 &&
		    gtk_icon_theme_has_icon(gtk_icon_theme_get_default(), map[i][1]))
			return map[i][1];
	return "package-x-generic";
}

static void on_action(GtkButton *b, gpointer data)
{
	Pkg *k = data;
	if (has_update(k)) {
		const char *args[] = {"upgrade", k->name, NULL};
		char *w = g_strdup_printf("Updating %s", k->name);
		mlpkg(w, args);
		g_free(w);
	} else if (k->installed) {
		const char *args[] = {"remove", k->name, NULL};
		char *w = g_strdup_printf("Removing %s", k->name);
		mlpkg(w, args);
		g_free(w);
	} else {
		const char *args[] = {"install", k->name, NULL};
		char *w = g_strdup_printf("Installing %s", k->name);
		mlpkg(w, args);
		g_free(w);
	}
}

static GtkWidget *pkg_row(Pkg *k)
{
	GtkWidget *row = gtk_list_box_row_new();
	g_object_set_data(G_OBJECT(row), "pkg", k);
	GtkWidget *h = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
	g_object_set(h, "margin", 8, NULL);
	gtk_box_pack_start(GTK_BOX(h), gtk_image_new_from_icon_name(cat_icon(k->category), GTK_ICON_SIZE_DND), FALSE, FALSE, 0);
	GtkWidget *v = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
	GtkWidget *title = gtk_label_new(NULL);
	char *m = g_markup_printf_escaped("<b>%s</b>  <small>%s%s%s</small>", k->name, k->version,
	                                  k->installed ? "  ·  installed" : (k->live ? "  ·  on the live medium" : ""),
	                                  has_update(k) ? "  ·  update available" : "");
	gtk_label_set_markup(GTK_LABEL(title), m);
	g_free(m);
	gtk_label_set_xalign(GTK_LABEL(title), 0);
	GtkWidget *desc = gtk_label_new(k->desc);
	gtk_label_set_xalign(GTK_LABEL(desc), 0);
	gtk_label_set_ellipsize(GTK_LABEL(desc), PANGO_ELLIPSIZE_END);
	gtk_style_context_add_class(gtk_widget_get_style_context(desc), "dim-label");
	gtk_box_pack_start(GTK_BOX(v), title, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(v), desc, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(h), v, TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(h), gtk_label_new(k->size), FALSE, FALSE, 0);
	const char *label = has_update(k) ? "Update" : k->installed ? "Remove" : k->live ? "Active" : "Install";
	GtkWidget *b = gtk_button_new_with_label(label);
	gtk_widget_set_size_request(b, 96, -1);
	gtk_widget_set_valign(b, GTK_ALIGN_CENTER);
	if (k->live)
		gtk_widget_set_sensitive(b, FALSE);
	else if (!k->installed)
		gtk_style_context_add_class(gtk_widget_get_style_context(b), "suggested-action");
	else if (!has_update(k))
		gtk_style_context_add_class(gtk_widget_get_style_context(b), "destructive-action");
	g_signal_connect(b, "clicked", G_CALLBACK(on_action), k);
	gtk_box_pack_end(GTK_BOX(h), b, FALSE, FALSE, 0);
	gtk_container_add(GTK_CONTAINER(row), h);
	return row;
}

static gboolean pkg_visible(GtkListBoxRow *row, gpointer data)
{
	Pkg *k = g_object_get_data(G_OBJECT(row), "pkg");
	if (!k)
		return TRUE;
	gboolean libs = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(libs_check));
	gboolean show;
	if (strcmp(current_cat, "Installed") == 0)
		show = k->installed && (libs || !k->autodep);
	else if (strcmp(current_cat, "Updates") == 0)
		show = has_update(k);
	else if (strcmp(current_cat, "All") == 0)
		show = libs || strcmp(k->category, "Libraries") != 0;
	else
		show = strcmp(k->category, current_cat) == 0;
	const char *q = gtk_entry_get_text(GTK_ENTRY(search));
	if (show && *q) {
		char *a = g_utf8_strdown(k->name, -1), *b = g_utf8_strdown(k->desc, -1), *n = g_utf8_strdown(q, -1);
		show = strstr(a, n) || strstr(b, n);
		g_free(a);
		g_free(b);
		g_free(n);
	}
	return show;
}

static gint pkg_sort(GtkListBoxRow *a, GtkListBoxRow *b, gpointer data)
{
	Pkg *x = g_object_get_data(G_OBJECT(a), "pkg"), *y = g_object_get_data(G_OBJECT(b), "pkg");
	return g_ascii_strcasecmp(x->name, y->name);
}

static void pkg_details(GtkListBox *box, GtkListBoxRow *row, gpointer data)
{
	Pkg *k = g_object_get_data(G_OBJECT(row), "pkg");
	GtkWidget *d = gtk_message_dialog_new(GTK_WINDOW(window), GTK_DIALOG_MODAL, GTK_MESSAGE_INFO, GTK_BUTTONS_CLOSE,
	                                      "%s %s", k->name, k->version);
	gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(d),
		"%s\n\nCategory: %s\nDownload size: %s\nInstalled: %s%s\nNeeds: %s",
		k->desc, k->category, k->size, k->installed ? k->installed : (k->live ? "active from the live medium" : "no"),
		k->autodep ? " (as a dependency)" : "", *k->deps ? k->deps : "nothing else");
	gtk_dialog_run(GTK_DIALOG(d));
	gtk_widget_destroy(d);
}

/* ------------------------------------------------------------------------ */
/* categories                                                               */
/* ------------------------------------------------------------------------ */

static GtkWidget *cat_row(const char *name, int count)
{
	GtkWidget *row = gtk_list_box_row_new();
	g_object_set_data_full(G_OBJECT(row), "cat", g_strdup(name), g_free);
	GtkWidget *h = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
	g_object_set(h, "margin", 7, "margin-start", 10, NULL);
	gtk_box_pack_start(GTK_BOX(h), gtk_image_new_from_icon_name(cat_icon(name), GTK_ICON_SIZE_MENU), FALSE, FALSE, 0);
	GtkWidget *l = gtk_label_new(name);
	gtk_label_set_xalign(GTK_LABEL(l), 0);
	gtk_box_pack_start(GTK_BOX(h), l, TRUE, TRUE, 0);
	char *c = g_strdup_printf("%d", count);
	GtkWidget *cl = gtk_label_new(c);
	g_free(c);
	gtk_style_context_add_class(gtk_widget_get_style_context(cl), "dim-label");
	gtk_box_pack_end(GTK_BOX(h), cl, FALSE, FALSE, 0);
	gtk_container_add(GTK_CONTAINER(row), h);
	return row;
}

static void cat_selected(GtkListBox *box, GtkListBoxRow *row, gpointer data)
{
	if (!row)
		return;
	g_free(current_cat);
	current_cat = g_strdup(g_object_get_data(G_OBJECT(row), "cat"));
	gtk_list_box_invalidate_filter(GTK_LIST_BOX(pkg_list));
}

static void clear(GtkWidget *box)
{
	GList *c = gtk_container_get_children(GTK_CONTAINER(box));
	for (GList *i = c; i; i = i->next)
		gtk_widget_destroy(i->data);
	g_list_free(c);
}

static void reload(void)
{
	load_data();
	clear(pkg_list);
	clear(cat_list);
	int installed = 0, updates = 0, apps = 0;
	GHashTable *counts = g_hash_table_new_full(g_str_hash, g_str_equal, NULL, NULL);
	for (guint i = 0; i < pkgs->len; i++) {
		Pkg *k = pkgs->pdata[i];
		gtk_container_add(GTK_CONTAINER(pkg_list), pkg_row(k));
		installed += k->installed && !k->autodep;
		updates += has_update(k);
		apps += strcmp(k->category, "Libraries") != 0;
		g_hash_table_insert(counts, k->category, GINT_TO_POINTER(GPOINTER_TO_INT(g_hash_table_lookup(counts, k->category)) + 1));
	}
	gtk_container_add(GTK_CONTAINER(cat_list), cat_row("All", apps));
	gtk_container_add(GTK_CONTAINER(cat_list), cat_row("Installed", installed));
	gtk_container_add(GTK_CONTAINER(cat_list), cat_row("Updates", updates));
	GList *names = g_list_sort(g_hash_table_get_keys(counts), (GCompareFunc)g_strcmp0);
	for (GList *i = names; i; i = i->next)
		if (strcmp(i->data, "Libraries") != 0)
			gtk_container_add(GTK_CONTAINER(cat_list), cat_row(i->data, GPOINTER_TO_INT(g_hash_table_lookup(counts, i->data))));
	if (g_hash_table_contains(counts, "Libraries"))
		gtk_container_add(GTK_CONTAINER(cat_list), cat_row("Libraries", GPOINTER_TO_INT(g_hash_table_lookup(counts, "Libraries"))));
	g_list_free(names);
	g_hash_table_destroy(counts);
	gtk_widget_show_all(cat_list);
	gtk_widget_show_all(pkg_list);
	/* keep the selected category */
	GList *rows = gtk_container_get_children(GTK_CONTAINER(cat_list));
	for (GList *i = rows; i; i = i->next)
		if (g_strcmp0(g_object_get_data(G_OBJECT(i->data), "cat"), current_cat) == 0)
			gtk_list_box_select_row(GTK_LIST_BOX(cat_list), i->data);
	g_list_free(rows);
	char *u = updates ? g_strdup_printf("Update all (%d)", updates) : g_strdup("Update all");
	gtk_button_set_label(GTK_BUTTON(update_all), u);
	g_free(u);
	gtk_widget_set_sensitive(update_all, updates > 0 && !busy);
	gtk_label_set_text(GTK_LABEL(placeholder), pkgs->len ? "Nothing matches."
	                   : "No package lists yet.\nClick \"Refresh\" to download them (needs the internet).");
	gtk_list_box_invalidate_filter(GTK_LIST_BOX(pkg_list));
}

static void on_refresh(GtkButton *b, gpointer d)
{
	const char *args[] = {"update", NULL};
	mlpkg("Refreshing package lists", args);
}

static void on_update_all(GtkButton *b, gpointer d)
{
	const char *args[] = {"upgrade", NULL};
	mlpkg("Updating all packages", args);
}

static void on_filter(GtkWidget *w, gpointer d)
{
	gtk_list_box_invalidate_filter(GTK_LIST_BOX(pkg_list));
}

static void on_details(GtkToggleButton *b, gpointer d)
{
	gtk_revealer_set_reveal_child(GTK_REVEALER(log_revealer), gtk_toggle_button_get_active(b));
}

int main(int argc, char **argv)
{
	gtk_init(&argc, &argv);
	current_cat = g_strdup("All");
	window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
	gtk_window_set_title(GTK_WINDOW(window), "Software");
	gtk_window_set_icon_name(GTK_WINDOW(window), "system-software-install");
	gtk_window_set_default_size(GTK_WINDOW(window), 980, 660);
	g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), NULL);

	GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
	/* top bar */
	GtkWidget *top = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
	g_object_set(top, "margin", 8, NULL);
	search = gtk_search_entry_new();
	gtk_entry_set_placeholder_text(GTK_ENTRY(search), "Search packages");
	gtk_box_pack_start(GTK_BOX(top), search, TRUE, TRUE, 0);
	libs_check = gtk_check_button_new_with_label("Show libraries");
	gtk_box_pack_start(GTK_BOX(top), libs_check, FALSE, FALSE, 0);
	GtkWidget *refresh = gtk_button_new_with_mnemonic("_Refresh");
	g_signal_connect(refresh, "clicked", G_CALLBACK(on_refresh), NULL);
	gtk_box_pack_start(GTK_BOX(top), refresh, FALSE, FALSE, 0);
	update_all = gtk_button_new_with_label("Update all");
	g_signal_connect(update_all, "clicked", G_CALLBACK(on_update_all), NULL);
	gtk_box_pack_start(GTK_BOX(top), update_all, FALSE, FALSE, 0);
	static const char *const file_buttons[][3] = {
		{"Install ._deb…", "deb", "Install Debian or Ubuntu packages (.deb files) you downloaded"},
		{"Install .r_pm…", "rpm", "Install RHEL, AlmaLinux, Rocky or Fedora packages (.rpm files) you downloaded"},
		{"Install .ml_p…", "mlp", "Install MicroLinux packages (.mlp files)"}};
	for (size_t i = 0; i < G_N_ELEMENTS(file_buttons); i++) {
		GtkWidget *fb = gtk_button_new_with_mnemonic(file_buttons[i][0]);
		gtk_widget_set_tooltip_text(fb, file_buttons[i][2]);
		g_signal_connect(fb, "clicked", G_CALLBACK(on_install_file), (gpointer)file_buttons[i][1]);
		gtk_box_pack_start(GTK_BOX(top), fb, FALSE, FALSE, 0);
	}
	gtk_box_pack_start(GTK_BOX(outer), top, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(outer), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 0);

	/* categories | packages */
	GtkWidget *main_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
	GtkWidget *csw = gtk_scrolled_window_new(NULL, NULL);
	gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(csw), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
	gtk_widget_set_size_request(csw, 210, -1);
	cat_list = gtk_list_box_new();
	g_signal_connect(cat_list, "row-selected", G_CALLBACK(cat_selected), NULL);
	gtk_container_add(GTK_CONTAINER(csw), cat_list);
	gtk_box_pack_start(GTK_BOX(main_box), csw, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(main_box), gtk_separator_new(GTK_ORIENTATION_VERTICAL), FALSE, FALSE, 0);
	GtkWidget *psw = gtk_scrolled_window_new(NULL, NULL);
	pkg_list = gtk_list_box_new();
	gtk_list_box_set_selection_mode(GTK_LIST_BOX(pkg_list), GTK_SELECTION_NONE);
	gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(pkg_list), FALSE);
	gtk_list_box_set_filter_func(GTK_LIST_BOX(pkg_list), pkg_visible, NULL, NULL);
	gtk_list_box_set_sort_func(GTK_LIST_BOX(pkg_list), pkg_sort, NULL, NULL);
	g_signal_connect(pkg_list, "row-activated", G_CALLBACK(pkg_details), NULL);
	placeholder = gtk_label_new("");
	gtk_label_set_justify(GTK_LABEL(placeholder), GTK_JUSTIFY_CENTER);
	gtk_widget_show(placeholder);
	gtk_list_box_set_placeholder(GTK_LIST_BOX(pkg_list), placeholder);
	gtk_container_add(GTK_CONTAINER(psw), pkg_list);
	gtk_box_pack_start(GTK_BOX(main_box), psw, TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(outer), main_box, TRUE, TRUE, 0);

	/* status line + output of mlpkg */
	gtk_box_pack_start(GTK_BOX(outer), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 0);
	GtkWidget *sbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
	g_object_set(sbar, "margin", 6, "margin-start", 12, NULL);
	spinner = gtk_spinner_new();
	status = gtk_label_new("Double-click a package for details. Dependencies are installed automatically.");
	gtk_label_set_xalign(GTK_LABEL(status), 0);
	gtk_label_set_ellipsize(GTK_LABEL(status), PANGO_ELLIPSIZE_END);
	details_btn = gtk_toggle_button_new_with_label("Details");
	g_signal_connect(details_btn, "toggled", G_CALLBACK(on_details), NULL);
	gtk_box_pack_start(GTK_BOX(sbar), spinner, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(sbar), status, TRUE, TRUE, 0);
	gtk_box_pack_end(GTK_BOX(sbar), details_btn, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(outer), sbar, FALSE, FALSE, 0);
	log_revealer = gtk_revealer_new();
	GtkWidget *lsw = gtk_scrolled_window_new(NULL, NULL);
	gtk_widget_set_size_request(lsw, -1, 150);
	log_view = gtk_text_view_new();
	gtk_text_view_set_editable(GTK_TEXT_VIEW(log_view), FALSE);
	gtk_text_view_set_monospace(GTK_TEXT_VIEW(log_view), TRUE);
	gtk_container_add(GTK_CONTAINER(lsw), log_view);
	gtk_container_add(GTK_CONTAINER(log_revealer), lsw);
	gtk_box_pack_start(GTK_BOX(outer), log_revealer, FALSE, FALSE, 0);

	g_signal_connect(search, "search-changed", G_CALLBACK(on_filter), NULL);
	g_signal_connect(libs_check, "toggled", G_CALLBACK(on_filter), NULL);
	gtk_container_add(GTK_CONTAINER(window), outer);
	reload();
	/* --install-deb: Software 1.1's name for it */
	gboolean debs = argc > 2 && (strcmp(argv[1], "--install") == 0 || strcmp(argv[1], "--install-deb") == 0);
	if (argc > 1 && !debs)
		gtk_entry_set_text(GTK_ENTRY(search), argv[1]);
	gtk_widget_show_all(window);
	if (debs) {
		/* absolute paths: sudo starts the installer in another directory */
		GPtrArray *a = g_ptr_array_new_with_free_func(g_free);
		for (int i = 2; i < argc; i++)
			g_ptr_array_add(a, g_canonicalize_filename(argv[i], NULL));
		g_ptr_array_add(a, NULL);
		install_files((char **)a->pdata);
		g_ptr_array_free(a, TRUE);
	}
	gtk_main();
	return 0;
}
