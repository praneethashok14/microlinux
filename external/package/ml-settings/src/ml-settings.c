/*
 * ml-settings - the MicroLinux settings application (GTK 3)
 *
 *   ml-settings [PAGE]          PAGE: network bluetooth display sound appearance
 *                               keyboard datetime users packages about
 *   ml-settings --askpass PROMPT    password dialog for sudo -A (see ml-askpass)
 *
 * The program runs as the desktop user. Everything that needs root runs
 * through "sudo -A", which asks for the password with ml-askpass when the
 * sudo rules require one. The actual work is done by the system's own tools
 * (netcfg, bluetoothctl, ml-display, setxkbmap, mlpkg, ...), so the settings
 * made here are the same as on the command line.
 */
#include <alsa/asoundlib.h>
#include <gtk/gtk.h>
#include <string.h>
#include <sys/statvfs.h>
#include <sys/sysinfo.h>
#include <sys/utsname.h>
#include <unistd.h>

#define ASKPASS "/usr/libexec/ml-askpass"
#define ZONEINFO "/usr/share/zoneinfo"

static GtkWidget *window, *status_label;

/* ------------------------------------------------------------------------ */
/* helpers                                                                  */
/* ------------------------------------------------------------------------ */

static void set_status(const char *fmt, ...) G_GNUC_PRINTF(1, 2);
static void set_status(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	char *s = g_strdup_vprintf(fmt, ap);
	va_end(ap);
	gtk_label_set_text(GTK_LABEL(status_label), s);
	g_free(s);
}

static char *config_path(const char *name)
{
	char *dir = g_build_filename(g_get_user_config_dir(), "microlinux", NULL);
	g_mkdir_with_parents(dir, 0755);
	char *p = g_build_filename(dir, name, NULL);
	g_free(dir);
	return p;
}

/* run a command and return its stdout (unprivileged, synchronous, for quick reads) */
static char *read_cmd(const char *const *argv)
{
	char *out = NULL;
	g_spawn_sync(NULL, (char **)argv, NULL, G_SPAWN_SEARCH_PATH | G_SPAWN_STDERR_TO_DEV_NULL,
	             NULL, NULL, &out, NULL, NULL, NULL);
	return out ? out : g_strdup("");
}

typedef void (*DoneFn)(gboolean ok, const char *output, gpointer data);
typedef struct {
	DoneFn fn;
	gpointer data;
} Job;

static void job_done(GObject *src, GAsyncResult *res, gpointer user)
{
	Job *job = user;
	char *out = NULL, *err = NULL;
	GError *e = NULL;
	gboolean ok = g_subprocess_communicate_utf8_finish(G_SUBPROCESS(src), res, &out, &err, &e);
	ok = ok && g_subprocess_get_successful(G_SUBPROCESS(src));
	GString *all = g_string_new(out ? out : "");
	if (err && *err)
		g_string_append(all, err);
	if (e) {
		g_string_append(all, e->message);
		g_error_free(e);
	}
	gdk_window_set_cursor(gtk_widget_get_window(window), NULL);
	if (job->fn)
		job->fn(ok, all->str, job->data);
	g_string_free(all, TRUE);
	g_free(out);
	g_free(err);
	g_free(job);
	g_object_unref(src);
}

/* Run argv in the background; as_root runs it through "sudo -A". INPUT, if
 * given, is written to the command's standard input. FN is called when it ends. */
static void run(const char *const *argv, gboolean as_root, const char *input, DoneFn fn, gpointer data)
{
	GPtrArray *a = g_ptr_array_new();
	if (as_root) {
		g_ptr_array_add(a, "sudo");
		g_ptr_array_add(a, "-A");
		g_ptr_array_add(a, "--");
	}
	for (int i = 0; argv[i]; i++)
		g_ptr_array_add(a, (gpointer)argv[i]);
	g_ptr_array_add(a, NULL);

	GSubprocessFlags flags = G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_PIPE;
	if (input)
		flags |= G_SUBPROCESS_FLAGS_STDIN_PIPE;
	GSubprocessLauncher *l = g_subprocess_launcher_new(flags);
	g_subprocess_launcher_setenv(l, "SUDO_ASKPASS", ASKPASS, TRUE);
	g_subprocess_launcher_setenv(l, "LC_ALL", "C", TRUE);
	GError *e = NULL;
	GSubprocess *p = g_subprocess_launcher_spawnv(l, (const char *const *)a->pdata, &e);
	g_object_unref(l);
	g_ptr_array_free(a, TRUE);
	if (!p) {
		if (fn)
			fn(FALSE, e->message, data);
		g_error_free(e);
		return;
	}
	GdkCursor *busy = gdk_cursor_new_for_display(gdk_display_get_default(), GDK_WATCH);
	gdk_window_set_cursor(gtk_widget_get_window(window), busy);
	g_object_unref(busy);
	Job *job = g_new0(Job, 1);
	job->fn = fn;
	job->data = data;
	g_subprocess_communicate_utf8_async(p, input, NULL, job_done, job);
}

/* open a terminal window running CMD (for interactive tools) */
static void run_in_terminal(const char *title, const char *cmd)
{
	const char *argv[] = {"qterminal", "-e", "sh", "-c", cmd, NULL};
	g_spawn_async(NULL, (char **)argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL);
}

static void show_text(const char *title, const char *text)
{
	GtkWidget *d = gtk_dialog_new_with_buttons(title, GTK_WINDOW(window), GTK_DIALOG_MODAL,
	                                           "_Close", GTK_RESPONSE_CLOSE, NULL);
	gtk_window_set_default_size(GTK_WINDOW(d), 640, 400);
	GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
	GtkWidget *tv = gtk_text_view_new();
	gtk_text_view_set_editable(GTK_TEXT_VIEW(tv), FALSE);
	gtk_text_view_set_monospace(GTK_TEXT_VIEW(tv), TRUE);
	gtk_text_buffer_set_text(gtk_text_view_get_buffer(GTK_TEXT_VIEW(tv)), text, -1);
	gtk_container_add(GTK_CONTAINER(sw), tv);
	gtk_widget_set_vexpand(sw, TRUE);
	gtk_box_pack_start(GTK_BOX(gtk_dialog_get_content_area(GTK_DIALOG(d))), sw, TRUE, TRUE, 0);
	gtk_widget_show_all(d);
	gtk_dialog_run(GTK_DIALOG(d));
	gtk_widget_destroy(d);
}

/* generic completion: status line on success, output window on failure */
static void report_done(gboolean ok, const char *output, gpointer data)
{
	const char *what = data;
	if (ok) {
		set_status("%s: done.", what);
	} else {
		set_status("%s: failed.", what);
		show_text(what, *output ? output : "The command failed.");
	}
}

/* a page: title, subtitle and a vertical box for the content */
static GtkWidget *page_new(const char *title, const char *subtitle, GtkWidget **body)
{
	GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
	gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(sw), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
	GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
	g_object_set(box, "margin", 24, NULL);
	GtkWidget *t = gtk_label_new(NULL);
	char *m = g_markup_printf_escaped("<span size='x-large' weight='bold'>%s</span>", title);
	gtk_label_set_markup(GTK_LABEL(t), m);
	g_free(m);
	gtk_label_set_xalign(GTK_LABEL(t), 0);
	gtk_box_pack_start(GTK_BOX(box), t, FALSE, FALSE, 0);
	if (subtitle) {
		GtkWidget *s = gtk_label_new(subtitle);
		gtk_label_set_xalign(GTK_LABEL(s), 0);
		gtk_label_set_line_wrap(GTK_LABEL(s), TRUE);
		gtk_style_context_add_class(gtk_widget_get_style_context(s), "dim-label");
		gtk_box_pack_start(GTK_BOX(box), s, FALSE, FALSE, 0);
	}
	gtk_container_add(GTK_CONTAINER(sw), box);
	*body = box;
	return sw;
}

static GtkWidget *section(GtkWidget *body, const char *title)
{
	GtkWidget *f = gtk_frame_new(NULL);
	GtkWidget *l = gtk_label_new(NULL);
	char *m = g_markup_printf_escaped("<b>%s</b>", title);
	gtk_label_set_markup(GTK_LABEL(l), m);
	g_free(m);
	gtk_frame_set_label_widget(GTK_FRAME(f), l);
	GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
	g_object_set(box, "margin", 12, NULL);
	gtk_container_add(GTK_CONTAINER(f), box);
	gtk_box_pack_start(GTK_BOX(body), f, FALSE, FALSE, 0);
	return box;
}

/* label on the left, widget on the right */
static GtkWidget *row(GtkWidget *box, const char *label, GtkWidget *w)
{
	GtkWidget *h = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
	GtkWidget *l = gtk_label_new(label);
	gtk_label_set_xalign(GTK_LABEL(l), 0);
	gtk_box_pack_start(GTK_BOX(h), l, TRUE, TRUE, 0);
	if (w)
		gtk_box_pack_end(GTK_BOX(h), w, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), h, FALSE, FALSE, 0);
	return l;
}

static GtkWidget *button_row(GtkWidget *box)
{
	GtkWidget *h = gtk_button_box_new(GTK_ORIENTATION_HORIZONTAL);
	gtk_button_box_set_layout(GTK_BUTTON_BOX(h), GTK_BUTTONBOX_START);
	gtk_box_set_spacing(GTK_BOX(h), 8);
	gtk_box_pack_start(GTK_BOX(box), h, FALSE, FALSE, 0);
	return h;
}

static GtkWidget *add_button(GtkWidget *bbox, const char *label, GCallback cb, gpointer data)
{
	GtkWidget *b = gtk_button_new_with_mnemonic(label);
	g_signal_connect(b, "clicked", cb, data);
	gtk_container_add(GTK_CONTAINER(bbox), b);
	return b;
}

static GtkWidget *mono_label(void)
{
	GtkWidget *l = gtk_label_new("");
	gtk_label_set_xalign(GTK_LABEL(l), 0);
	gtk_label_set_selectable(GTK_LABEL(l), TRUE);
	gtk_style_context_add_class(gtk_widget_get_style_context(l), "monospace");
	return l;
}

/* ask for a text (password=TRUE hides it); returns NULL on cancel */
static char *ask_text(const char *title, const char *prompt, gboolean password)
{
	GtkWidget *d = gtk_dialog_new_with_buttons(title, GTK_WINDOW(window), GTK_DIALOG_MODAL,
	                                           "_Cancel", GTK_RESPONSE_CANCEL, "_OK", GTK_RESPONSE_OK, NULL);
	gtk_dialog_set_default_response(GTK_DIALOG(d), GTK_RESPONSE_OK);
	GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(d));
	g_object_set(box, "margin", 12, "spacing", 8, NULL);
	gtk_box_pack_start(GTK_BOX(box), gtk_label_new(prompt), FALSE, FALSE, 0);
	GtkWidget *e = gtk_entry_new();
	gtk_entry_set_visibility(GTK_ENTRY(e), !password);
	gtk_entry_set_activates_default(GTK_ENTRY(e), TRUE);
	gtk_box_pack_start(GTK_BOX(box), e, FALSE, FALSE, 0);
	gtk_widget_show_all(d);
	char *r = NULL;
	if (gtk_dialog_run(GTK_DIALOG(d)) == GTK_RESPONSE_OK)
		r = g_strdup(gtk_entry_get_text(GTK_ENTRY(e)));
	gtk_widget_destroy(d);
	return r;
}

/* ------------------------------------------------------------------------ */
/* Network                                                                  */
/* ------------------------------------------------------------------------ */

static GtkWidget *net_ifaces, *wifi_list, *wifi_hint;

static void net_refresh(void)
{
	const char *argv[] = {"ip", "-br", "addr", NULL};
	char *out = read_cmd(argv);
	gtk_label_set_text(GTK_LABEL(net_ifaces), g_strstrip(out));
	g_free(out);
}

static void wifi_scanned(gboolean ok, const char *output, gpointer data)
{
	GList *rows = gtk_container_get_children(GTK_CONTAINER(wifi_list));
	for (GList *r = rows; r; r = r->next)
		gtk_widget_destroy(r->data);
	g_list_free(rows);
	if (!ok) {
		gtk_label_set_text(GTK_LABEL(wifi_hint), output);
		set_status("Wi-Fi scan failed.");
		return;
	}
	char **lines = g_strsplit(output, "\n", -1);
	int n = 0;
	for (char **l = lines; *l; l++) {
		char *dbm = strstr(*l, " dBm  ");
		if (!dbm)
			continue;
		char *ssid = dbm + 6;
		char *sig = g_strndup(*l, dbm - *l);
		g_strstrip(sig);
		GtkWidget *rowbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
		g_object_set(rowbox, "margin", 6, NULL);
		GtkWidget *name = gtk_label_new(ssid);
		gtk_label_set_xalign(GTK_LABEL(name), 0);
		char *s = g_strdup_printf("%s dBm", sig);
		gtk_box_pack_start(GTK_BOX(rowbox), name, TRUE, TRUE, 0);
		gtk_box_pack_end(GTK_BOX(rowbox), gtk_label_new(s), FALSE, FALSE, 0);
		g_free(s);
		g_free(sig);
		g_object_set_data_full(G_OBJECT(rowbox), "ssid", g_strdup(ssid), g_free);
		gtk_list_box_insert(GTK_LIST_BOX(wifi_list), rowbox, -1);
		n++;
	}
	g_strfreev(lines);
	gtk_widget_show_all(wifi_list);
	gtk_label_set_text(GTK_LABEL(wifi_hint), n ? "Select a network and click Connect." : "No networks found.");
	set_status("Wi-Fi: %d network(s) found.", n);
}

static void wifi_scan(GtkButton *b, gpointer d)
{
	const char *argv[] = {"netcfg", "wifi-scan", NULL};
	set_status("Scanning for Wi-Fi networks ...");
	run(argv, TRUE, NULL, wifi_scanned, NULL);
}

static void wifi_connected(gboolean ok, const char *output, gpointer data)
{
	net_refresh();
	if (ok) {
		set_status("Wi-Fi connected and saved: it reconnects at every boot.");
	} else {
		set_status("Wi-Fi connection failed.");
		show_text("Wi-Fi", output);
	}
}

static void wifi_connect(GtkButton *b, gpointer d)
{
	GtkListBoxRow *r = gtk_list_box_get_selected_row(GTK_LIST_BOX(wifi_list));
	if (!r) {
		set_status("Select a Wi-Fi network first.");
		return;
	}
	const char *ssid = g_object_get_data(G_OBJECT(gtk_bin_get_child(GTK_BIN(r))), "ssid");
	char *prompt = g_strdup_printf("Password for \"%s\" (leave empty for an open network):", ssid);
	char *pass = ask_text("Wi-Fi", prompt, TRUE);
	g_free(prompt);
	if (!pass)
		return;
	if (*pass && strlen(pass) < 8) {
		set_status("Wi-Fi passwords have at least 8 characters.");
		g_free(pass);
		return;
	}
	const char *argv[] = {"netcfg", "wifi", ssid, *pass ? pass : NULL, NULL};
	set_status("Connecting to %s ...", ssid);
	run(argv, TRUE, NULL, wifi_connected, NULL);
	g_free(pass);
}

static void net_test_done(gboolean ok, const char *output, gpointer data)
{
	set_status(ok ? "Connection test passed." : "Connection test found problems.");
	show_text("Connection test", output);
}

static void net_test(GtkButton *b, gpointer d)
{
	const char *argv[] = {"netcfg", "test", NULL};
	set_status("Testing the connection ...");
	run(argv, FALSE, NULL, net_test_done, NULL);
}

static void net_refresh_cb(GtkButton *b, gpointer d) { net_refresh(); }

static GtkWidget *page_network(void)
{
	GtkWidget *body, *page = page_new("Network", "Wired connections are configured automatically (DHCP).", &body);
	GtkWidget *s = section(body, "Connections");
	net_ifaces = mono_label();
	gtk_box_pack_start(GTK_BOX(s), net_ifaces, FALSE, FALSE, 0);
	GtkWidget *bb = button_row(s);
	add_button(bb, "_Refresh", G_CALLBACK(net_refresh_cb), NULL);
	add_button(bb, "_Test connection", G_CALLBACK(net_test), NULL);

	s = section(body, "Wi-Fi");
	wifi_hint = gtk_label_new("Click Scan to look for networks.");
	gtk_label_set_xalign(GTK_LABEL(wifi_hint), 0);
	gtk_label_set_line_wrap(GTK_LABEL(wifi_hint), TRUE);
	gtk_box_pack_start(GTK_BOX(s), wifi_hint, FALSE, FALSE, 0);
	GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
	gtk_widget_set_size_request(sw, -1, 180);
	wifi_list = gtk_list_box_new();
	gtk_container_add(GTK_CONTAINER(sw), wifi_list);
	gtk_box_pack_start(GTK_BOX(s), sw, FALSE, FALSE, 0);
	bb = button_row(s);
	add_button(bb, "_Scan", G_CALLBACK(wifi_scan), NULL);
	add_button(bb, "_Connect", G_CALLBACK(wifi_connect), NULL);
	net_refresh();
	return page;
}

/* ------------------------------------------------------------------------ */
/* Bluetooth                                                                */
/* ------------------------------------------------------------------------ */

static GtkWidget *bt_power, *bt_list, *bt_hint;
static gboolean bt_updating;

static void bt_devices_done(gboolean ok, const char *output, gpointer data)
{
	GList *rows = gtk_container_get_children(GTK_CONTAINER(bt_list));
	for (GList *r = rows; r; r = r->next)
		gtk_widget_destroy(r->data);
	g_list_free(rows);
	char **lines = g_strsplit(output, "\n", -1);
	int n = 0;
	for (char **l = lines; *l; l++) {
		char mac[18];
		if (strncmp(*l, "Device ", 7) != 0 || strlen(*l) < 24)
			continue;
		g_strlcpy(mac, *l + 7, sizeof mac);
		GtkWidget *label = gtk_label_new(*l + 7);
		gtk_label_set_xalign(GTK_LABEL(label), 0);
		g_object_set(label, "margin", 6, NULL);
		g_object_set_data_full(G_OBJECT(label), "mac", g_strdup(mac), g_free);
		gtk_list_box_insert(GTK_LIST_BOX(bt_list), label, -1);
		n++;
	}
	g_strfreev(lines);
	gtk_widget_show_all(bt_list);
	if (n)
		gtk_label_set_text(GTK_LABEL(bt_hint), "Select a device. Put it in pairing mode before clicking Pair.");
}

static void bt_list_devices(void)
{
	const char *argv[] = {"bluetoothctl", "devices", NULL};
	run(argv, TRUE, NULL, bt_devices_done, NULL);
}

static void bt_show_done(gboolean ok, const char *output, gpointer data)
{
	if (!ok || !strstr(output, "Controller")) {
		gtk_label_set_text(GTK_LABEL(bt_hint), "No Bluetooth adapter found (or its driver/firmware is missing).");
		gtk_widget_set_sensitive(bt_power, FALSE);
		return;
	}
	bt_updating = TRUE;
	gtk_switch_set_active(GTK_SWITCH(bt_power), strstr(output, "Powered: yes") != NULL);
	bt_updating = FALSE;
	bt_list_devices();
}

static void bt_refresh(void)
{
	const char *argv[] = {"bluetoothctl", "show", NULL};
	run(argv, TRUE, NULL, bt_show_done, NULL);
}

static void bt_power_done(gboolean ok, const char *output, gpointer data)
{
	set_status(ok ? "Bluetooth power changed." : "Could not change Bluetooth power.");
	bt_refresh();
}

static gboolean bt_power_set(GtkSwitch *sw, gboolean state, gpointer d)
{
	if (bt_updating)
		return FALSE;
	const char *argv[] = {"bluetoothctl", "power", state ? "on" : "off", NULL};
	run(argv, TRUE, NULL, bt_power_done, NULL);
	return FALSE;
}

static void bt_scan_done(gboolean ok, const char *output, gpointer data)
{
	set_status("Bluetooth scan finished.");
	bt_list_devices();
}

static void bt_scan(GtkButton *b, gpointer d)
{
	const char *argv[] = {"bluetoothctl", "--timeout", "12", "scan", "on", NULL};
	set_status("Scanning for Bluetooth devices (12 seconds) ...");
	run(argv, TRUE, NULL, bt_scan_done, NULL);
}

static const char *bt_selected(void)
{
	GtkListBoxRow *r = gtk_list_box_get_selected_row(GTK_LIST_BOX(bt_list));
	return r ? g_object_get_data(G_OBJECT(gtk_bin_get_child(GTK_BIN(r))), "mac") : NULL;
}

static void bt_action_done(gboolean ok, const char *output, gpointer data)
{
	set_status(ok ? "Bluetooth: done." : "Bluetooth: failed.");
	if (!ok)
		show_text("Bluetooth", output);
	bt_list_devices();
}

static void bt_pair(GtkButton *b, gpointer d)
{
	const char *mac = bt_selected();
	if (!mac) {
		set_status("Select a device first.");
		return;
	}
	const char *argv[] = {"sh", "-c",
	                      "bluetoothctl --timeout 20 pair \"$1\" && bluetoothctl trust \"$1\" && "
	                      "bluetoothctl --timeout 15 connect \"$1\"",
	                      "sh", mac, NULL};
	set_status("Pairing with %s ...", mac);
	run(argv, TRUE, NULL, bt_action_done, NULL);
}

static void bt_connect(GtkButton *b, gpointer d)
{
	const char *mac = bt_selected();
	if (!mac) {
		set_status("Select a device first.");
		return;
	}
	const char *argv[] = {"bluetoothctl", "--timeout", "15", "connect", mac, NULL};
	set_status("Connecting to %s ...", mac);
	run(argv, TRUE, NULL, bt_action_done, NULL);
}

static void bt_remove(GtkButton *b, gpointer d)
{
	const char *mac = bt_selected();
	if (!mac) {
		set_status("Select a device first.");
		return;
	}
	const char *argv[] = {"bluetoothctl", "remove", mac, NULL};
	run(argv, TRUE, NULL, bt_action_done, NULL);
}

static GtkWidget *page_bluetooth(void)
{
	GtkWidget *body, *page = page_new("Bluetooth", "Keyboards, mice, game controllers and other devices.", &body);
	GtkWidget *s = section(body, "Adapter");
	bt_power = gtk_switch_new();
	g_signal_connect(bt_power, "state-set", G_CALLBACK(bt_power_set), NULL);
	row(s, "Bluetooth", bt_power);
	s = section(body, "Devices");
	bt_hint = gtk_label_new("Turn Bluetooth on and click Scan.");
	gtk_label_set_xalign(GTK_LABEL(bt_hint), 0);
	gtk_label_set_line_wrap(GTK_LABEL(bt_hint), TRUE);
	gtk_box_pack_start(GTK_BOX(s), bt_hint, FALSE, FALSE, 0);
	GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
	gtk_widget_set_size_request(sw, -1, 180);
	bt_list = gtk_list_box_new();
	gtk_container_add(GTK_CONTAINER(sw), bt_list);
	gtk_box_pack_start(GTK_BOX(s), sw, FALSE, FALSE, 0);
	GtkWidget *bb = button_row(s);
	add_button(bb, "_Scan", G_CALLBACK(bt_scan), NULL);
	add_button(bb, "_Pair", G_CALLBACK(bt_pair), NULL);
	add_button(bb, "C_onnect", G_CALLBACK(bt_connect), NULL);
	add_button(bb, "_Remove", G_CALLBACK(bt_remove), NULL);
	return page;
}

/* ------------------------------------------------------------------------ */
/* Display                                                                  */
/* ------------------------------------------------------------------------ */

static GtkWidget *disp_combo, *disp_current;

static void disp_refresh(void)
{
	const char *argv[] = {"xrandr", "--query", NULL};
	char *out = read_cmd(argv);
	char **lines = g_strsplit(out, "\n", -1);
	gboolean in_output = FALSE;
	char *current = NULL, *output = NULL;
	gtk_combo_box_text_remove_all(GTK_COMBO_BOX_TEXT(disp_combo));
	GHashTable *seen = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
	int n = 0;
	for (char **l = lines; *l; l++) {
		if (**l != ' ') {
			if (output && in_output)
				break;   /* only the first connected output */
			in_output = strstr(*l, " connected") != NULL;
			if (in_output)
				output = g_strndup(*l, strcspn(*l, " "));
			continue;
		}
		if (!in_output)
			continue;
		char mode[32];
		if (sscanf(*l, " %31s", mode) != 1 || !strchr(mode, 'x') || g_hash_table_contains(seen, mode))
			continue;
		g_hash_table_add(seen, g_strdup(mode));
		gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(disp_combo), mode, mode);
		if (strchr(*l, '*'))
			current = g_strdup(mode);
		n++;
	}
	if (current)
		gtk_combo_box_set_active_id(GTK_COMBO_BOX(disp_combo), current);
	char *s = g_strdup_printf("%s: %s", output ? output : "no display", current ? current : "unknown");
	gtk_label_set_text(GTK_LABEL(disp_current), s);
	g_free(s);
	g_hash_table_destroy(seen);
	g_strfreev(lines);
	g_free(out);
	g_free(current);
	g_free(output);
}

static void disp_done(gboolean ok, const char *output, gpointer data)
{
	disp_refresh();
	report_done(ok, output, "Display");
}

static void disp_apply(GtkButton *b, gpointer d)
{
	const char *mode = gtk_combo_box_get_active_id(GTK_COMBO_BOX(disp_combo));
	if (!mode)
		return;
	const char *argv[] = {"ml-display", "set", mode, NULL};
	run(argv, FALSE, NULL, disp_done, NULL);
}

static void disp_auto(GtkButton *b, gpointer d)
{
	const char *argv[] = {"sh", "-c", "rm -f \"$HOME/.config/ml-resolution\"; ml-display auto", NULL};
	run(argv, FALSE, NULL, disp_done, NULL);
}

static GtkWidget *page_display(void)
{
	GtkWidget *body, *page = page_new("Display", "The resolution is remembered and set again at every login.", &body);
	GtkWidget *s = section(body, "Resolution");
	disp_current = gtk_label_new("");
	row(s, "Current", disp_current);
	disp_combo = gtk_combo_box_text_new();
	row(s, "Resolution", disp_combo);
	GtkWidget *bb = button_row(s);
	add_button(bb, "_Apply", G_CALLBACK(disp_apply), NULL);
	add_button(bb, "A_utomatic", G_CALLBACK(disp_auto), NULL);
	disp_refresh();
	return page;
}

/* ------------------------------------------------------------------------ */
/* Sound                                                                    */
/* ------------------------------------------------------------------------ */

static snd_mixer_t *mixer;
static snd_mixer_elem_t *mixer_elem;
static GtkWidget *snd_scale, *snd_mute;
static gboolean snd_updating;

/* no sound card is a normal case here; don't let ALSA print about it */
static void alsa_quiet(const char *file, int line, const char *function, int err, const char *fmt, ...) {}

static gboolean snd_open(void)
{
	static const char *const names[] = {"Master", "PCM", "Speaker", "Headphone", "Digital", NULL};
	snd_lib_error_set_handler(alsa_quiet);
	if (snd_mixer_open(&mixer, 0) < 0)
		return FALSE;
	if (snd_mixer_attach(mixer, "default") < 0 || snd_mixer_selem_register(mixer, NULL, NULL) < 0 ||
	    snd_mixer_load(mixer) < 0) {
		snd_mixer_close(mixer);
		mixer = NULL;
		return FALSE;
	}
	for (int i = 0; names[i] && !mixer_elem; i++) {
		snd_mixer_selem_id_t *id;
		snd_mixer_selem_id_alloca(&id);
		snd_mixer_selem_id_set_name(id, names[i]);
		snd_mixer_elem_t *e = snd_mixer_find_selem(mixer, id);
		if (e && snd_mixer_selem_has_playback_volume(e))
			mixer_elem = e;
	}
	for (snd_mixer_elem_t *e = snd_mixer_first_elem(mixer); e && !mixer_elem; e = snd_mixer_elem_next(e))
		if (snd_mixer_selem_has_playback_volume(e))
			mixer_elem = e;
	return mixer_elem != NULL;
}

static void snd_read(void)
{
	long min, max, v;
	int sw = 1;
	snd_mixer_handle_events(mixer);
	snd_mixer_selem_get_playback_volume_range(mixer_elem, &min, &max);
	snd_mixer_selem_get_playback_volume(mixer_elem, SND_MIXER_SCHN_FRONT_LEFT, &v);
	if (snd_mixer_selem_has_playback_switch(mixer_elem))
		snd_mixer_selem_get_playback_switch(mixer_elem, SND_MIXER_SCHN_FRONT_LEFT, &sw);
	snd_updating = TRUE;
	gtk_range_set_value(GTK_RANGE(snd_scale), max > min ? 100.0 * (v - min) / (max - min) : 0);
	gtk_switch_set_active(GTK_SWITCH(snd_mute), !sw);
	snd_updating = FALSE;
}

/* Laptop codecs route Master -> Speaker / Headphone -> PCM, each with its own
 * mute switch: when sound is wanted, switch on every output path (the codec's
 * auto-mute still silences the speaker when headphones are plugged in). */
static void snd_unmute_paths(void)
{
	static const char *const paths[] = {"Master", "Speaker", "Headphone", "PCM", "Front", "Line Out", NULL};
	for (snd_mixer_elem_t *e = snd_mixer_first_elem(mixer); e; e = snd_mixer_elem_next(e)) {
		const char *n = snd_mixer_selem_get_name(e);
		for (int i = 0; paths[i]; i++) {
			if (strcmp(n, paths[i]) != 0)
				continue;
			if (snd_mixer_selem_has_playback_switch(e))
				snd_mixer_selem_set_playback_switch_all(e, 1);
			/* a path left at 0 would keep everything silent: bring it to 80% */
			long min, max, v;
			if (e != mixer_elem && snd_mixer_selem_has_playback_volume(e)) {
				snd_mixer_selem_get_playback_volume_range(e, &min, &max);
				snd_mixer_selem_get_playback_volume(e, SND_MIXER_SCHN_FRONT_LEFT, &v);
				if (v <= min)
					snd_mixer_selem_set_playback_volume_all(e, min + (max - min) * 8 / 10);
			}
		}
	}
}

static void snd_volume_changed(GtkRange *r, gpointer d)
{
	long min, max;
	if (snd_updating)
		return;
	if (gtk_range_get_value(r) > 0) {
		snd_unmute_paths();
		snd_updating = TRUE;
		gtk_switch_set_active(GTK_SWITCH(snd_mute), FALSE);
		snd_updating = FALSE;
	}
	snd_mixer_selem_get_playback_volume_range(mixer_elem, &min, &max);
	snd_mixer_selem_set_playback_volume_all(mixer_elem, min + (long)((max - min) * gtk_range_get_value(r) / 100.0 + 0.5));
}

static gboolean snd_mute_set(GtkSwitch *s, gboolean state, gpointer d)
{
	if (snd_updating)
		return FALSE;
	if (!state)
		snd_unmute_paths();
	else if (snd_mixer_selem_has_playback_switch(mixer_elem))
		snd_mixer_selem_set_playback_switch_all(mixer_elem, 0);
	return FALSE;
}

static void snd_test_done(gboolean ok, const char *output, gpointer data)
{
	if (ok)
		set_status("Test sound played (front left, then front right).");
	else
		report_done(FALSE, output, "Test sound");
}

static void snd_test(GtkButton *b, gpointer d)
{
	const char *argv[] = {"speaker-test", "-t", "wav", "-c", "2", "-l", "1", NULL};
	set_status("Playing a test sound ...");
	run(argv, FALSE, NULL, snd_test_done, NULL);
}

static GtkWidget *page_sound(void)
{
	GtkWidget *body, *page = page_new("Sound", NULL, &body);
	GtkWidget *s = section(body, "Output");
	if (!snd_open()) {
		GtkWidget *l = gtk_label_new("No sound card with a volume control was found.");
		gtk_label_set_xalign(GTK_LABEL(l), 0);
		gtk_box_pack_start(GTK_BOX(s), l, FALSE, FALSE, 0);
		return page;
	}
	char *card = g_strdup_printf("Volume (%s)", snd_mixer_selem_get_name(mixer_elem));
	snd_scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 100, 1);
	gtk_widget_set_size_request(snd_scale, 300, -1);
	gtk_scale_set_value_pos(GTK_SCALE(snd_scale), GTK_POS_RIGHT);
	g_signal_connect(snd_scale, "value-changed", G_CALLBACK(snd_volume_changed), NULL);
	row(s, card, snd_scale);
	g_free(card);
	snd_mute = gtk_switch_new();
	g_signal_connect(snd_mute, "state-set", G_CALLBACK(snd_mute_set), NULL);
	row(s, "Mute", snd_mute);
	add_button(button_row(s), "_Test sound", G_CALLBACK(snd_test), NULL);
	snd_read();
	return page;
}

/* ------------------------------------------------------------------------ */
/* Appearance                                                               */
/* ------------------------------------------------------------------------ */

static GtkWidget *bg_default, *bg_solid, *bg_picture, *bg_color, *bg_file, *dark_switch;

/* the wallpaper is drawn by PCManFM-Qt (LXQt desktop): pcmanfm-qt passes the
   change to the running desktop */
static void set_wallpaper(const char *file, const char *mode)
{
	char *arg = g_strdup_printf("--set-wallpaper=%s", file);
	char *m = g_strdup_printf("--wallpaper-mode=%s", mode);
	const char *argv[] = {"pcmanfm-qt", "--profile=lxqt", arg, m, NULL};
	GError *e = NULL;
	if (g_spawn_async(NULL, (char **)argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, &e)) {
		set_status("Wallpaper changed.");
	} else {
		set_status("Could not change the wallpaper: %s", e->message);
		g_error_free(e);
	}
	g_free(arg);
	g_free(m);
}

static void bg_apply(GtkButton *b, gpointer d)
{
	if (gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(bg_solid))) {
		/* a solid colour is a one-colour picture */
		GdkRGBA c;
		gtk_color_chooser_get_rgba(GTK_COLOR_CHOOSER(bg_color), &c);
		GdkPixbuf *pb = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, 16, 16);
		gdk_pixbuf_fill(pb, ((guint32)(c.red * 255 + 0.5) << 24) | ((guint32)(c.green * 255 + 0.5) << 16) |
		                    ((guint32)(c.blue * 255 + 0.5) << 8) | 0xff);
		char *path = config_path("wallpaper-colour.png");
		GError *e = NULL;
		if (gdk_pixbuf_save(pb, path, "png", &e, NULL)) {
			set_wallpaper(path, "stretch");
		} else {
			set_status("Could not save: %s", e->message);
			g_error_free(e);
		}
		g_free(path);
		g_object_unref(pb);
	} else if (gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(bg_picture))) {
		char *f = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(bg_file));
		if (!f) {
			set_status("Choose a picture first.");
			return;
		}
		set_wallpaper(f, "zoom");
		g_free(f);
	} else {
		set_wallpaper("/usr/share/microlinux/wallpaper.png", "stretch");
	}
}

static void appearance_more(GtkButton *b, gpointer d)
{
	const char *argv[] = {"lxqt-config-appearance", NULL};
	g_spawn_async(NULL, (char **)argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL);
}

/* dark mode: GTK applications started from now on (and this window) */
static gboolean dark_set(GtkSwitch *s, gboolean state, gpointer d)
{
	char *dir = g_build_filename(g_get_user_config_dir(), "gtk-3.0", NULL);
	char *path = g_build_filename(dir, "settings.ini", NULL);
	g_mkdir_with_parents(dir, 0755);
	GKeyFile *k = g_key_file_new();
	if (!g_key_file_load_from_file(k, path, G_KEY_FILE_KEEP_COMMENTS, NULL))
		g_key_file_load_from_file(k, "/etc/gtk-3.0/settings.ini", G_KEY_FILE_KEEP_COMMENTS, NULL);
	g_key_file_set_boolean(k, "Settings", "gtk-application-prefer-dark-theme", state);
	g_key_file_save_to_file(k, path, NULL);
	g_key_file_free(k);
	g_object_set(gtk_settings_get_default(), "gtk-application-prefer-dark-theme", state, NULL);
	set_status(state ? "Dark mode on (for applications opened from now on)." : "Dark mode off.");
	g_free(path);
	g_free(dir);
	return FALSE;
}

static GtkWidget *page_appearance(void)
{
	GtkWidget *body, *page = page_new("Appearance", NULL, &body);
	GtkWidget *s = section(body, "Wallpaper");
	bg_default = gtk_radio_button_new_with_label(NULL, "MicroLinux default (gradient)");
	bg_solid = gtk_radio_button_new_with_label_from_widget(GTK_RADIO_BUTTON(bg_default), "Solid colour");
	bg_picture = gtk_radio_button_new_with_label_from_widget(GTK_RADIO_BUTTON(bg_default), "Picture");
	gtk_box_pack_start(GTK_BOX(s), bg_default, FALSE, FALSE, 0);
	GtkWidget *h = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
	GdkRGBA blue = {0.18, 0.20, 0.25, 1};
	bg_color = gtk_color_button_new_with_rgba(&blue);
	gtk_box_pack_start(GTK_BOX(h), bg_solid, TRUE, TRUE, 0);
	gtk_box_pack_end(GTK_BOX(h), bg_color, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(s), h, FALSE, FALSE, 0);
	h = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
	bg_file = gtk_file_chooser_button_new("Choose a picture", GTK_FILE_CHOOSER_ACTION_OPEN);
	GtkFileFilter *f = gtk_file_filter_new();
	gtk_file_filter_set_name(f, "Pictures (PNG, JPEG, SVG)");
	gtk_file_filter_add_mime_type(f, "image/png");
	gtk_file_filter_add_mime_type(f, "image/jpeg");
	gtk_file_filter_add_mime_type(f, "image/svg+xml");
	gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(bg_file), f);
	gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(bg_file), g_get_home_dir());
	gtk_widget_set_size_request(bg_file, 260, -1);
	gtk_box_pack_start(GTK_BOX(h), bg_picture, TRUE, TRUE, 0);
	gtk_box_pack_end(GTK_BOX(h), bg_file, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(s), h, FALSE, FALSE, 0);
	add_button(button_row(s), "_Apply", G_CALLBACK(bg_apply), NULL);

	s = section(body, "Style");
	dark_switch = gtk_switch_new();
	gboolean dark = FALSE;
	g_object_get(gtk_settings_get_default(), "gtk-application-prefer-dark-theme", &dark, NULL);
	gtk_switch_set_active(GTK_SWITCH(dark_switch), dark);
	g_signal_connect(dark_switch, "state-set", G_CALLBACK(dark_set), NULL);
	row(s, "Dark mode for GTK applications", dark_switch);
	add_button(button_row(s), "_Desktop theme, icons and fonts...", G_CALLBACK(appearance_more), NULL);
	return page;
}

/* ------------------------------------------------------------------------ */
/* Keyboard                                                                 */
/* ------------------------------------------------------------------------ */

static const char *const layouts[][2] = {
	{"us", "English (US)"}, {"gb", "English (UK)"}, {"de", "German"}, {"fr", "French"},
	{"es", "Spanish"}, {"latam", "Spanish (Latin America)"}, {"it", "Italian"}, {"pt", "Portuguese"},
	{"br", "Portuguese (Brazil)"}, {"nl", "Dutch"}, {"be", "Belgian"}, {"ch", "Swiss"},
	{"at", "Austrian"}, {"se", "Swedish"}, {"no", "Norwegian"}, {"dk", "Danish"}, {"fi", "Finnish"},
	{"is", "Icelandic"}, {"ie", "Irish"}, {"pl", "Polish"}, {"cz", "Czech"}, {"sk", "Slovak"},
	{"hu", "Hungarian"}, {"ro", "Romanian"}, {"si", "Slovenian"}, {"hr", "Croatian"}, {"rs", "Serbian"},
	{"bg", "Bulgarian"}, {"gr", "Greek"}, {"tr", "Turkish"}, {"ru", "Russian"}, {"ua", "Ukrainian"},
	{"il", "Hebrew"}, {"ara", "Arabic"}, {"ir", "Persian"}, {"in", "Indian"}, {"jp", "Japanese"},
	{"kr", "Korean"}, {"cn", "Chinese"}, {"th", "Thai"}, {"vn", "Vietnamese"}, {"ca", "Canadian (French)"},
	{NULL, NULL}};
static GtkWidget *kb_combo;

static void kb_done(gboolean ok, const char *output, gpointer data)
{
	char *layout = data;
	if (ok) {
		char *path = config_path("keyboard");
		g_file_set_contents(path, layout, -1, NULL);
		g_free(path);
		set_status("Keyboard layout: %s (kept for future logins).", layout);
	} else {
		report_done(FALSE, output, "Keyboard");
	}
	g_free(layout);
}

static void kb_apply(GtkButton *b, gpointer d)
{
	const char *layout = gtk_combo_box_get_active_id(GTK_COMBO_BOX(kb_combo));
	if (!layout)
		return;
	const char *argv[] = {"setxkbmap", layout, NULL};
	run(argv, FALSE, NULL, kb_done, g_strdup(layout));
}

static GtkWidget *page_keyboard(void)
{
	GtkWidget *body, *page = page_new("Keyboard", "The layout applies to the desktop and is kept for future logins.", &body);
	GtkWidget *s = section(body, "Layout");
	kb_combo = gtk_combo_box_text_new();
	for (int i = 0; layouts[i][0]; i++)
		gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(kb_combo), layouts[i][0], layouts[i][1]);
	const char *argv[] = {"setxkbmap", "-query", NULL};
	char *q = read_cmd(argv), *cur = strstr(q, "layout:");
	if (cur) {
		cur += 7;
		while (*cur == ' ')
			cur++;
		cur[strcspn(cur, ",\n")] = 0;
		if (!gtk_combo_box_set_active_id(GTK_COMBO_BOX(kb_combo), cur)) {
			gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(kb_combo), cur, cur);
			gtk_combo_box_set_active_id(GTK_COMBO_BOX(kb_combo), cur);
		}
	}
	g_free(q);
	row(s, "Keyboard layout", kb_combo);
	add_button(button_row(s), "_Apply", G_CALLBACK(kb_apply), NULL);
	GtkWidget *e = gtk_entry_new();
	gtk_entry_set_placeholder_text(GTK_ENTRY(e), "Type here to try the layout");
	gtk_box_pack_start(GTK_BOX(s), e, FALSE, FALSE, 0);
	return page;
}

/* ------------------------------------------------------------------------ */
/* Date & time                                                              */
/* ------------------------------------------------------------------------ */

static GtkWidget *dt_clock, *dt_region, *dt_city;
static const char *const tz_regions[] = {"Africa", "America", "Antarctica", "Asia", "Atlantic",
                                         "Australia", "Europe", "Indian", "Pacific", "UTC", NULL};

static gboolean dt_tick(gpointer d)
{
	GDateTime *now = g_date_time_new_now_local();
	char *s = g_date_time_format(now, "%A %d %B %Y   %H:%M:%S   (%Z, UTC%:z)");
	gtk_label_set_text(GTK_LABEL(dt_clock), s);
	g_free(s);
	g_date_time_unref(now);
	return G_SOURCE_CONTINUE;
}

static void tz_collect(const char *dir, const char *prefix, GPtrArray *out)
{
	GDir *d = g_dir_open(dir, 0, NULL);
	if (!d)
		return;
	const char *n;
	while ((n = g_dir_read_name(d))) {
		char *p = g_build_filename(dir, n, NULL);
		char *name = *prefix ? g_strdup_printf("%s/%s", prefix, n) : g_strdup(n);
		if (g_file_test(p, G_FILE_TEST_IS_DIR))
			tz_collect(p, name, out);
		else if (g_ascii_isupper(n[0]))
			g_ptr_array_add(out, g_strdup(name));
		g_free(name);
		g_free(p);
	}
	g_dir_close(d);
}

static gint cmp_str(gconstpointer a, gconstpointer b)
{
	return g_strcmp0(*(char *const *)a, *(char *const *)b);
}

static void dt_done(gboolean ok, const char *output, gpointer data)
{
	report_done(ok, output, data);
	/* glibc reads /etc/localtime again when TZ changes */
	g_setenv("TZ", ":/etc/localtime", TRUE);
	tzset();
	dt_tick(NULL);
}

/* region chosen: list its cities (a few dozen, instead of ~400 zones in one list) */
static void dt_region_changed(GtkComboBox *c, gpointer select)
{
	const char *region = gtk_combo_box_get_active_id(c);
	gtk_combo_box_text_remove_all(GTK_COMBO_BOX_TEXT(dt_city));
	if (!region)
		return;
	if (strcmp(region, "UTC") == 0) {
		gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(dt_city), "UTC", "UTC");
	} else {
		GPtrArray *zones = g_ptr_array_new_with_free_func(g_free);
		char *p = g_build_filename(ZONEINFO, region, NULL);
		tz_collect(p, region, zones);
		g_free(p);
		g_ptr_array_sort(zones, cmp_str);
		for (guint i = 0; i < zones->len; i++) {
			const char *z = zones->pdata[i];
			char *label = g_strdelimit(g_strdup(z + strlen(region) + 1), "_", ' ');
			gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(dt_city), z, label);
			g_free(label);
		}
		g_ptr_array_free(zones, TRUE);
	}
	if (!select || !gtk_combo_box_set_active_id(GTK_COMBO_BOX(dt_city), select))
		gtk_combo_box_set_active(GTK_COMBO_BOX(dt_city), 0);
}

static void dt_apply(GtkButton *b, gpointer d)
{
	const char *tz = gtk_combo_box_get_active_id(GTK_COMBO_BOX(dt_city));
	if (!tz || strstr(tz, ".."))
		return;
	const char *argv[] = {"sh", "-c",
	                      "ln -sf \"" ZONEINFO "/$1\" /etc/localtime && echo \"$1\" > /etc/timezone", "sh", tz, NULL};
	run(argv, TRUE, NULL, dt_done, "Time zone");
}

static void dt_sync(GtkButton *b, gpointer d)
{
	const char *argv[] = {"ntpd", "-n", "-q", "-p", "pool.ntp.org", NULL};
	set_status("Synchronising the clock ...");
	run(argv, TRUE, NULL, dt_done, "Time synchronisation");
}

static GtkWidget *page_datetime(void)
{
	GtkWidget *body, *page = page_new("Date & Time", "The clock is set from the internet at every boot.", &body);
	GtkWidget *s = section(body, "Clock");
	dt_clock = gtk_label_new("");
	gtk_label_set_xalign(GTK_LABEL(dt_clock), 0);
	gtk_box_pack_start(GTK_BOX(s), dt_clock, FALSE, FALSE, 0);
	add_button(button_row(s), "_Synchronise now", G_CALLBACK(dt_sync), NULL);
	dt_tick(NULL);
	g_timeout_add_seconds(1, dt_tick, NULL);

	s = section(body, "Time zone");
	dt_region = gtk_combo_box_text_new();
	dt_city = gtk_combo_box_text_new();
	for (int i = 0; tz_regions[i]; i++)
		gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(dt_region), tz_regions[i], tz_regions[i]);
	char *link = g_file_read_link("/etc/localtime", NULL);
	const char *cur = link && g_str_has_prefix(link, ZONEINFO "/") ? link + strlen(ZONEINFO) + 1 : "UTC";
	char *region = g_strndup(cur, strcspn(cur, "/"));
	g_signal_connect(dt_region, "changed", G_CALLBACK(dt_region_changed), NULL);
	g_signal_handlers_block_by_func(dt_region, dt_region_changed, NULL);
	gtk_combo_box_set_active_id(GTK_COMBO_BOX(dt_region), region);
	g_signal_handlers_unblock_by_func(dt_region, dt_region_changed, NULL);
	dt_region_changed(GTK_COMBO_BOX(dt_region), (gpointer)cur);
	g_free(region);
	g_free(link);
	row(s, "Region", dt_region);
	row(s, "City", dt_city);
	add_button(button_row(s), "_Apply", G_CALLBACK(dt_apply), NULL);
	return page;
}

/* ------------------------------------------------------------------------ */
/* Users                                                                    */
/* ------------------------------------------------------------------------ */

static GtkWidget *pw_new, *pw_again;

static void pw_done(gboolean ok, const char *output, gpointer data)
{
	if (ok) {
		gtk_entry_set_text(GTK_ENTRY(pw_new), "");
		gtk_entry_set_text(GTK_ENTRY(pw_again), "");
	}
	report_done(ok, output, "Password change");
}

static void pw_apply(GtkButton *b, gpointer d)
{
	const char *a = gtk_entry_get_text(GTK_ENTRY(pw_new)), *c = gtk_entry_get_text(GTK_ENTRY(pw_again));
	if (strcmp(a, c) != 0) {
		set_status("The two passwords are different.");
		return;
	}
	if (strlen(a) < 4) {
		set_status("Use at least 4 characters.");
		return;
	}
	if (strchr(a, ':') || strchr(a, '\n')) {
		set_status("The password can't contain ':' or line breaks.");
		return;
	}
	char *input = g_strdup_printf("%s:%s\n", g_get_user_name(), a);
	const char *argv[] = {"chpasswd", NULL};
	run(argv, TRUE, input, pw_done, NULL);
	g_free(input);
}

static GtkWidget *page_users(void)
{
	GtkWidget *body, *page = page_new("Users", NULL, &body);
	GtkWidget *s = section(body, "Your account");
	char *who = g_strdup_printf("%s (%s)", g_get_user_name(), g_get_real_name());
	row(s, "User", gtk_label_new(who));
	g_free(who);
	const char *argv[] = {"id", "-Gn", NULL};
	char *groups = read_cmd(argv);
	row(s, "Groups", gtk_label_new(g_strstrip(groups)));
	g_free(groups);

	s = section(body, "Change password");
	GtkWidget *hint = gtk_label_new("You may be asked for your current password first. "
	                                "This password is also the one sudo asks for.");
	gtk_label_set_xalign(GTK_LABEL(hint), 0);
	gtk_label_set_line_wrap(GTK_LABEL(hint), TRUE);
	gtk_box_pack_start(GTK_BOX(s), hint, FALSE, FALSE, 0);
	pw_new = gtk_entry_new();
	gtk_entry_set_visibility(GTK_ENTRY(pw_new), FALSE);
	row(s, "New password", pw_new);
	pw_again = gtk_entry_new();
	gtk_entry_set_visibility(GTK_ENTRY(pw_again), FALSE);
	row(s, "Repeat", pw_again);
	add_button(button_row(s), "_Change password", G_CALLBACK(pw_apply), NULL);
	return page;
}

/* ------------------------------------------------------------------------ */
/* Packages                                                                 */
/* ------------------------------------------------------------------------ */

enum { P_NAME, P_VERSION, P_SIZE, P_STATE, P_DESC, P_SECTION, P_COLS };
static GtkListStore *pkg_store;
static GtkTreeModel *pkg_filter;
static GtkWidget *pkg_search, *pkg_libs, *pkg_view, *pkg_hint;

static gboolean pkg_visible(GtkTreeModel *m, GtkTreeIter *it, gpointer d)
{
	char *name, *desc, *section;
	gtk_tree_model_get(m, it, P_NAME, &name, P_DESC, &desc, P_SECTION, &section, -1);
	gboolean show = name != NULL;
	if (show && !gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(pkg_libs)))
		show = g_strcmp0(section, "lib") != 0;
	const char *q = gtk_entry_get_text(GTK_ENTRY(pkg_search));
	if (show && *q) {
		char *hay = g_utf8_strdown(desc ? desc : "", -1), *n = g_utf8_strdown(name, -1), *needle = g_utf8_strdown(q, -1);
		show = strstr(n, needle) || strstr(hay, needle);
		g_free(hay);
		g_free(n);
		g_free(needle);
	}
	g_free(name);
	g_free(desc);
	g_free(section);
	return show;
}

static char *pkg_state(const char *name)
{
	char *info = g_strdup_printf("/var/lib/mlpkg/installed/%s.info", name);
	char *active = g_strdup_printf("/run/mlpkg/active/%s", name);
	const char *s = g_file_test(info, G_FILE_TEST_EXISTS) ? "installed"
	                : g_file_test(active, G_FILE_TEST_EXISTS) ? "on live medium" : "";
	g_free(info);
	g_free(active);
	return g_strdup(s);
}

static void pkg_load(void)
{
	gtk_list_store_clear(pkg_store);
	GHashTable *seen = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
	GDir *d = g_dir_open("/var/cache/mlpkg", 0, NULL);
	const char *n;
	int count = 0;
	while (d && (n = g_dir_read_name(d))) {
		if (!g_str_has_prefix(n, "INDEX."))
			continue;
		char *p = g_build_filename("/var/cache/mlpkg", n, NULL), *text = NULL;
		if (g_file_get_contents(p, &text, NULL, NULL)) {
			char **lines = g_strsplit(text, "\n", -1);
			for (char **l = lines; *l; l++) {
				char **f = g_strsplit(*l, "|", 8);
				if (g_strv_length(f) >= 6 && !g_hash_table_contains(seen, f[0])) {
					g_hash_table_add(seen, g_strdup(f[0]));
					double mb = g_ascii_strtod(f[4], NULL) / 1048576.0;
					char *size = mb >= 1 ? g_strdup_printf("%.0f MB", mb) : g_strdup_printf("%.0f KB", mb * 1024 + 0.5);
					char *state = pkg_state(f[0]);
					gtk_list_store_insert_with_values(pkg_store, NULL, -1, P_NAME, f[0], P_VERSION, f[1],
					                                  P_SIZE, size, P_STATE, state, P_DESC, f[5],
					                                  P_SECTION, f[7] ? f[7] : "app", -1);
					g_free(size);
					g_free(state);
					count++;
				}
				g_strfreev(f);
			}
			g_strfreev(lines);
		}
		g_free(text);
		g_free(p);
	}
	if (d)
		g_dir_close(d);
	g_hash_table_destroy(seen);
	gtk_label_set_text(GTK_LABEL(pkg_hint), count ? "Double-click a package for details. Dependencies are installed automatically."
	                                              : "No package lists yet: click \"Refresh lists\" (needs the internet).");
	gtk_tree_model_filter_refilter(GTK_TREE_MODEL_FILTER(pkg_filter));
}

static void pkg_filter_changed(GtkWidget *w, gpointer d)
{
	gtk_tree_model_filter_refilter(GTK_TREE_MODEL_FILTER(pkg_filter));
}

static void pkg_done(gboolean ok, const char *output, gpointer data)
{
	pkg_load();
	report_done(ok, output, data);
	g_free(data);
}

static void pkg_update(GtkButton *b, gpointer d)
{
	const char *argv[] = {"mlpkg", "update", NULL};
	set_status("Downloading package lists ...");
	run(argv, TRUE, NULL, pkg_done, g_strdup("Package lists"));
}

static char *pkg_selected(void)
{
	GtkTreeIter it;
	GtkTreeModel *m;
	char *name = NULL;
	if (gtk_tree_selection_get_selected(gtk_tree_view_get_selection(GTK_TREE_VIEW(pkg_view)), &m, &it))
		gtk_tree_model_get(m, &it, P_NAME, &name, -1);
	return name;
}

static void pkg_action(GtkButton *b, gpointer verb)
{
	char *name = pkg_selected();
	if (!name) {
		set_status("Select a package first.");
		return;
	}
	const char *argv[] = {"mlpkg", verb, name, NULL};
	set_status("%s %s ...", strcmp(verb, "install") == 0 ? "Installing" : "Removing", name);
	run(argv, TRUE, NULL, pkg_done, g_strdup_printf("%s %s", (char *)verb, name));
	g_free(name);
}

static void pkg_info_done(gboolean ok, const char *output, gpointer data)
{
	show_text("Package", output);
}

static void pkg_activated(GtkTreeView *v, GtkTreePath *p, GtkTreeViewColumn *c, gpointer d)
{
	char *name = pkg_selected();
	if (!name)
		return;
	const char *argv[] = {"mlpkg", "info", name, NULL};
	run(argv, FALSE, NULL, pkg_info_done, NULL);
	g_free(name);
}

/* the full package browser: start it, or install it from the repository */
static void pkg_software_done(gboolean ok, const char *output, gpointer data)
{
	pkg_load();
	if (ok) {
		const char *argv[] = {"ml-software", NULL};
		g_spawn_async(NULL, (char **)argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL);
		set_status("Software installed.");
	} else {
		report_done(FALSE, output, "Installing Software");
	}
}

static void pkg_software(GtkButton *b, gpointer d)
{
	char *path = g_find_program_in_path("ml-software");
	if (path) {
		const char *argv[] = {path, NULL};
		g_spawn_async(NULL, (char **)argv, NULL, 0, NULL, NULL, NULL, NULL);
		g_free(path);
		return;
	}
	GtkWidget *q = gtk_message_dialog_new(GTK_WINDOW(window), GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION,
	                                      GTK_BUTTONS_YES_NO, "Install Software?");
	gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(q),
		"Software is a package browser with categories, search and updates. "
		"It is installed from the package repository (about 50 KB).");
	gint r = gtk_dialog_run(GTK_DIALOG(q));
	gtk_widget_destroy(q);
	if (r != GTK_RESPONSE_YES)
		return;
	const char *argv[] = {"mlpkg", "install", "ml-software", NULL};
	set_status("Installing Software ...");
	run(argv, TRUE, NULL, pkg_software_done, NULL);
}

static void pkg_column(const char *title, int col, gboolean expand)
{
	GtkCellRenderer *r = gtk_cell_renderer_text_new();
	if (expand)
		g_object_set(r, "ellipsize", PANGO_ELLIPSIZE_END, NULL);
	GtkTreeViewColumn *c = gtk_tree_view_column_new_with_attributes(title, r, "text", col, NULL);
	gtk_tree_view_column_set_sort_column_id(c, col);
	gtk_tree_view_column_set_resizable(c, TRUE);
	gtk_tree_view_column_set_expand(c, expand);
	gtk_tree_view_append_column(GTK_TREE_VIEW(pkg_view), c);
}

static GtkWidget *page_packages(void)
{
	GtkWidget *body, *page = page_new("Packages", NULL, &body);
	gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(page), GTK_POLICY_NEVER, GTK_POLICY_NEVER);
	pkg_hint = gtk_label_new("");
	gtk_label_set_xalign(GTK_LABEL(pkg_hint), 0);
	gtk_box_pack_start(GTK_BOX(body), pkg_hint, FALSE, FALSE, 0);
	GtkWidget *h = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
	pkg_search = gtk_search_entry_new();
	gtk_widget_set_hexpand(pkg_search, TRUE);
	pkg_libs = gtk_check_button_new_with_label("Show libraries");
	gtk_box_pack_start(GTK_BOX(h), pkg_search, TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(h), pkg_libs, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(body), h, FALSE, FALSE, 0);

	pkg_store = gtk_list_store_new(P_COLS, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING,
	                               G_TYPE_STRING, G_TYPE_STRING);
	gtk_tree_sortable_set_sort_column_id(GTK_TREE_SORTABLE(pkg_store), P_NAME, GTK_SORT_ASCENDING);
	pkg_filter = gtk_tree_model_filter_new(GTK_TREE_MODEL(pkg_store), NULL);
	gtk_tree_model_filter_set_visible_func(GTK_TREE_MODEL_FILTER(pkg_filter), pkg_visible, NULL, NULL);
	GtkTreeModel *sorted = gtk_tree_model_sort_new_with_model(pkg_filter);
	pkg_view = gtk_tree_view_new_with_model(sorted);
	pkg_column("Name", P_NAME, FALSE);
	pkg_column("Version", P_VERSION, FALSE);
	pkg_column("Size", P_SIZE, FALSE);
	pkg_column("State", P_STATE, FALSE);
	pkg_column("Description", P_DESC, TRUE);
	g_signal_connect(pkg_view, "row-activated", G_CALLBACK(pkg_activated), NULL);
	GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
	gtk_container_add(GTK_CONTAINER(sw), pkg_view);
	gtk_widget_set_vexpand(sw, TRUE);
	gtk_box_pack_start(GTK_BOX(body), sw, TRUE, TRUE, 0);
	GtkWidget *bb = button_row(body);
	add_button(bb, "_Install", G_CALLBACK(pkg_action), "install");
	add_button(bb, "_Remove", G_CALLBACK(pkg_action), "remove");
	add_button(bb, "Refresh _lists", G_CALLBACK(pkg_update), NULL);
	add_button(bb, "_Software ...", G_CALLBACK(pkg_software), NULL);
	g_signal_connect(pkg_search, "search-changed", G_CALLBACK(pkg_filter_changed), NULL);
	g_signal_connect(pkg_libs, "toggled", G_CALLBACK(pkg_filter_changed), NULL);
	pkg_load();
	return page;
}

/* ------------------------------------------------------------------------ */
/* About                                                                    */
/* ------------------------------------------------------------------------ */

static char *os_release(const char *key)
{
	char *text = NULL, *v = NULL;
	if (g_file_get_contents("/etc/os-release", &text, NULL, NULL)) {
		char **lines = g_strsplit(text, "\n", -1);
		size_t kl = strlen(key);
		for (char **l = lines; *l && !v; l++)
			if (strncmp(*l, key, kl) == 0 && (*l)[kl] == '=')
				v = g_shell_unquote(*l + kl + 1, NULL);
		g_strfreev(lines);
	}
	g_free(text);
	return v ? v : g_strdup("MicroLinux");
}

static char *cpu_model(void)
{
	char *text = NULL, *v = NULL;
	if (g_file_get_contents("/proc/cpuinfo", &text, NULL, NULL)) {
		char **lines = g_strsplit(text, "\n", -1);
		int cpus = 0;
		for (char **l = lines; *l; l++) {
			if (g_str_has_prefix(*l, "processor"))
				cpus++;
			if (!v && (g_str_has_prefix(*l, "model name") || g_str_has_prefix(*l, "Model")) && strchr(*l, ':'))
				v = g_strstrip(g_strdup(strchr(*l, ':') + 1));
		}
		g_strfreev(lines);
		if (!v) {   /* ARM: no model name in /proc/cpuinfo */
			struct utsname u;
			uname(&u);
			v = g_strdup(u.machine);
		}
		char *s = g_strdup_printf("%s (%d core%s)", v, cpus, cpus == 1 ? "" : "s");
		g_free(v);
		v = s;
	}
	g_free(text);
	return v ? v : g_strdup("unknown");
}

static void about_install(GtkButton *b, gpointer d)
{
	const char *argv[] = {"ml-installer", NULL};
	g_spawn_async(NULL, (char **)argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL);
}

static void about_update(GtkButton *b, gpointer d)
{
	run_in_terminal("Update MicroLinux", "sudo mlpkg system-update; echo; printf 'Press Enter to close'; read x");
}

static void about_persist(GtkButton *b, gpointer d)
{
	run_in_terminal("Keep changes on USB", "sudo ml-persist; echo; printf 'Press Enter to close'; read x");
}

static void about_log(GtkButton *b, gpointer d)
{
	run_in_terminal("System log", "sudo ml-log -f");
}

static GtkWidget *page_about(void)
{
	GtkWidget *body, *page = page_new("About", NULL, &body);
	GtkWidget *s = section(body, "System");
	struct utsname u;
	struct sysinfo si;
	struct statvfs fs;
	uname(&u);
	sysinfo(&si);
	char *name = os_release("PRETTY_NAME"), *cpu = cpu_model();
	char *kernel = g_strdup_printf("Linux %s", u.release);
	char *mem = g_strdup_printf("%.1f GB", si.totalram * (double)si.mem_unit / 1073741824.0);
	char *disk = statvfs("/", &fs) == 0
	                 ? g_strdup_printf("%.1f GB free of %.1f GB", fs.f_bavail * (double)fs.f_frsize / 1073741824.0,
	                                   fs.f_blocks * (double)fs.f_frsize / 1073741824.0)
	                 : g_strdup("unknown");
	char *up = g_strdup_printf("%ld h %ld min", si.uptime / 3600, si.uptime / 60 % 60);
	gboolean live = g_file_test("/live/medium", G_FILE_TEST_EXISTS);
	row(s, "System", gtk_label_new(name));
	row(s, "Kernel", gtk_label_new(kernel));
	row(s, "Processor", gtk_label_new(cpu));
	row(s, "Memory", gtk_label_new(mem));
	row(s, "Disk (/)", gtk_label_new(disk));
	row(s, "Computer name", gtk_label_new(g_get_host_name()));
	row(s, "Running", gtk_label_new(live ? "from the live medium" : "installed on disk"));
	row(s, "Up for", gtk_label_new(up));
	g_free(name);
	g_free(cpu);
	g_free(kernel);
	g_free(mem);
	g_free(disk);
	g_free(up);

	s = section(body, "Tools");
	GtkWidget *bb = button_row(s);
	if (live) {
		add_button(bb, "_Install to disk ...", G_CALLBACK(about_install), NULL);
		add_button(bb, "_Keep changes on USB ...", G_CALLBACK(about_persist), NULL);
	} else {
		add_button(bb, "_Update system ...", G_CALLBACK(about_update), NULL);
	}
	add_button(bb, "System _log", G_CALLBACK(about_log), NULL);
	return page;
}

/* ------------------------------------------------------------------------ */
/* sudo password dialog (ml-askpass)                                        */
/* ------------------------------------------------------------------------ */

static int askpass(const char *prompt)
{
	GtkWidget *d = gtk_dialog_new_with_buttons("Password required", NULL, 0, "_Cancel", GTK_RESPONSE_CANCEL,
	                                           "_OK", GTK_RESPONSE_OK, NULL);
	gtk_window_set_keep_above(GTK_WINDOW(d), TRUE);
	gtk_window_set_position(GTK_WINDOW(d), GTK_WIN_POS_CENTER);
	gtk_dialog_set_default_response(GTK_DIALOG(d), GTK_RESPONSE_OK);
	GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(d));
	g_object_set(box, "margin", 16, "spacing", 10, NULL);
	GtkWidget *l = gtk_label_new(NULL);
	char *m = g_markup_printf_escaped("<b>Administrator rights are needed.</b>\n%s",
	                                  prompt && *prompt ? prompt : "Password:");
	gtk_label_set_markup(GTK_LABEL(l), m);
	g_free(m);
	gtk_label_set_xalign(GTK_LABEL(l), 0);
	gtk_box_pack_start(GTK_BOX(box), l, FALSE, FALSE, 0);
	GtkWidget *e = gtk_entry_new();
	gtk_entry_set_visibility(GTK_ENTRY(e), FALSE);
	gtk_entry_set_activates_default(GTK_ENTRY(e), TRUE);
	gtk_box_pack_start(GTK_BOX(box), e, FALSE, FALSE, 0);
	gtk_widget_show_all(d);
	int rc = 1;
	if (gtk_dialog_run(GTK_DIALOG(d)) == GTK_RESPONSE_OK) {
		printf("%s\n", gtk_entry_get_text(GTK_ENTRY(e)));
		fflush(stdout);
		rc = 0;
	}
	gtk_widget_destroy(d);
	return rc;
}

/* ------------------------------------------------------------------------ */

/* Pages are built the first time they are shown, so Settings opens quickly.
 * Each stack child is an empty box holding its page constructor. */
typedef GtkWidget *(*PageFn)(void);

static void page_build(GtkWidget *holder)
{
	PageFn make = g_object_get_data(G_OBJECT(holder), "make");
	if (!make)
		return;
	g_object_set_data(G_OBJECT(holder), "make", NULL);
	gint64 t0 = g_get_monotonic_time();
	GtkWidget *p = make();
	if (g_getenv("ML_SETTINGS_TIMING"))
		g_printerr("page %-10s %6.1f ms\n", gtk_widget_get_name(holder), (g_get_monotonic_time() - t0) / 1000.0);
	gtk_box_pack_start(GTK_BOX(holder), p, TRUE, TRUE, 0);
	gtk_widget_show_all(p);
}

/* Bluetooth needs sudo: query it only when its page is opened, so that opening
 * Settings never asks for a password by itself */
static void page_changed(GObject *stack, GParamSpec *pspec, gpointer d)
{
	static gboolean bt_loaded;
	GtkWidget *child = gtk_stack_get_visible_child(GTK_STACK(stack));
	const char *name = gtk_stack_get_visible_child_name(GTK_STACK(stack));
	if (child)
		page_build(child);
	gtk_label_set_text(GTK_LABEL(status_label), "");
	if (g_strcmp0(name, "bluetooth") == 0 && !bt_loaded) {
		bt_loaded = TRUE;
		bt_refresh();
	}
}

int main(int argc, char **argv)
{
	gtk_init(&argc, &argv);
	if (argc > 1 && strcmp(argv[1], "--askpass") == 0)
		return askpass(argc > 2 ? argv[2] : NULL);

	window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
	gtk_window_set_title(GTK_WINDOW(window), "Settings");
	gtk_window_set_icon_name(GTK_WINDOW(window), "preferences-system");
	gtk_window_set_default_size(GTK_WINDOW(window), 920, 620);
	g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), NULL);

	GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
	GtkWidget *main_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
	GtkWidget *stack = gtk_stack_new();
	gtk_stack_set_transition_type(GTK_STACK(stack), GTK_STACK_TRANSITION_TYPE_CROSSFADE);
	GtkWidget *sidebar = gtk_stack_sidebar_new();
	gtk_stack_sidebar_set_stack(GTK_STACK_SIDEBAR(sidebar), GTK_STACK(stack));
	gtk_widget_set_size_request(sidebar, 170, -1);
	gtk_box_pack_start(GTK_BOX(main_box), sidebar, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(main_box), gtk_separator_new(GTK_ORIENTATION_VERTICAL), FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(main_box), stack, TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(outer), main_box, TRUE, TRUE, 0);
	status_label = gtk_label_new("");
	gtk_label_set_xalign(GTK_LABEL(status_label), 0);
	gtk_label_set_ellipsize(GTK_LABEL(status_label), PANGO_ELLIPSIZE_END);
	g_object_set(status_label, "margin", 6, "margin-start", 12, NULL);
	gtk_box_pack_start(GTK_BOX(outer), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(outer), status_label, FALSE, FALSE, 0);
	gtk_container_add(GTK_CONTAINER(window), outer);
	gtk_widget_show_all(window);   /* the pages need a realized window for the busy cursor */

	struct {
		const char *id, *title;
		PageFn make;
	} pages[] = {
		{"network", "Network", page_network},       {"bluetooth", "Bluetooth", page_bluetooth},
		{"display", "Display", page_display},       {"sound", "Sound", page_sound},
		{"appearance", "Appearance", page_appearance}, {"keyboard", "Keyboard", page_keyboard},
		{"datetime", "Date & Time", page_datetime}, {"users", "Users", page_users},
		{"packages", "Packages", page_packages},    {"about", "About", page_about},
	};
	for (size_t i = 0; i < G_N_ELEMENTS(pages); i++) {
		GtkWidget *holder = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
		gtk_widget_set_name(holder, pages[i].id);
		g_object_set_data(G_OBJECT(holder), "make", pages[i].make);
		gtk_widget_show(holder);
		gtk_stack_add_titled(GTK_STACK(stack), holder, pages[i].id, pages[i].title);
	}
	g_signal_connect(stack, "notify::visible-child-name", G_CALLBACK(page_changed), NULL);
	if (argc > 1)
		gtk_stack_set_visible_child_name(GTK_STACK(stack), argv[1]);
	page_changed(G_OBJECT(stack), NULL, NULL);   /* build the page shown first */
	gtk_main();
	return 0;
}
