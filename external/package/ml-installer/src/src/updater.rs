//! ml-updater: the window that updates an installed MicroLinux, opened by
//! Settings > System Update and by the update notification.
//!
//! Like the installer it only shows what happens. The update is done by
//! ml-system-update, the same script as "sudo mlpkg system-update" on the
//! command line:
//!   ml-system-update --info         what an update would do, as key=value lines
//!   sudo mlpkg system-update -y     the update itself

use eframe::egui::{self, Color32, RichText};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::process::{Command, Stdio};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;

/// ml-system-update's "==> " progress lines, in order
const STEPS: [(&str, &str); 5] = [
    ("checking", "Checking the release"),
    ("downloading", "Downloading"),
    ("updating system files", "Updating the system files"),
    ("updating kernel", "Updating the kernel and boot loader"),
    ("updating packages", "Updating the installed packages"),
];
const RED: Color32 = Color32::from_rgb(0xc0, 0x1c, 0x28);
const GREEN: Color32 = Color32::from_rgb(0x26, 0xa2, 0x69);

#[derive(Clone, Copy, PartialEq)]
enum Page {
    Checking,
    Details,
    Update,
}

enum Msg {
    /// the --info lines, or why there are none; and whether sudo needs a password
    Info(Result<HashMap<String, String>, String>, bool),
    BadPassword,
    Line(String),
    /// curl's download progress, in percent
    Progress(f32),
    Exit(bool),
}

struct App {
    page: Page,
    info: HashMap<String, String>,
    error: Option<String>,
    need_password: bool,
    password: String,
    password_error: bool,
    focus_password: bool,
    tx: Sender<Msg>,
    rx: Receiver<Msg>,
    running: bool,
    log: Vec<String>,
    step: usize,
    progress: Option<f32>,
    /// the system files are updated (the package update may still fail)
    updated: bool,
    result: Option<bool>,
}

fn info() -> Result<HashMap<String, String>, String> {
    let out = Command::new("/usr/libexec/ml-system-update")
        .arg("--info")
        .env("LC_ALL", "C")
        .output()
        .map_err(|e| format!("ml-system-update: {e}"))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        let last = err.trim().lines().last().unwrap_or("unknown error");
        return Err(last.trim_start_matches("mlpkg system-update: ").to_string());
    }
    Ok(String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|l| l.split_once('='))
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect())
}

fn megabytes(bytes: &str) -> Option<String> {
    let b: f64 = bytes.parse().ok()?;
    Some(if b >= 1e9 { format!("{:.1} GB", b / 1e9) } else { format!("{} MB", (b / 1e6).ceil().max(1.0)) })
}

/// send the lines of STREAM; curl's progress bar ends its updates with '\r'
fn forward(stream: impl Read, tx: Sender<Msg>, ctx: egui::Context) {
    let mut line = Vec::new();
    for b in std::io::BufReader::new(stream).bytes().map_while(Result::ok) {
        if b != b'\n' && b != b'\r' {
            line.push(b);
            continue;
        }
        let l = String::from_utf8_lossy(&line).trim_end().to_string();
        line.clear();
        if l.is_empty() {
            continue;
        }
        let pct = l.strip_suffix('%').and_then(|s| s.split_whitespace().last()).and_then(|s| s.parse().ok());
        let _ = tx.send(match pct {
            Some(p) if l.starts_with('#') || l.starts_with(' ') => Msg::Progress(p),
            _ => Msg::Line(l),
        });
        ctx.request_repaint();
    }
}

impl App {
    fn new(cc: &eframe::CreationContext) -> Self {
        cc.egui_ctx.set_theme(egui::Theme::Light);
        cc.egui_ctx.set_zoom_factor(1.15);
        let (tx, rx) = channel();
        let mut app = App {
            page: Page::Checking,
            info: HashMap::new(),
            error: None,
            need_password: false,
            password: String::new(),
            password_error: false,
            focus_password: false,
            tx,
            rx,
            running: false,
            log: Vec::new(),
            step: 0,
            progress: None,
            updated: false,
            result: None,
        };
        app.check(&cc.egui_ctx);
        app
    }

    fn check(&mut self, ctx: &egui::Context) {
        self.page = Page::Checking;
        let (tx, ctx) = (self.tx.clone(), ctx.clone());
        thread::spawn(move || {
            let need_password = !Command::new("sudo")
                .args(["-n", "true"])
                .stderr(Stdio::null())
                .status()
                .is_ok_and(|s| s.success());
            let _ = tx.send(Msg::Info(info(), need_password));
            ctx.request_repaint();
        });
    }

    fn get(&self, key: &str) -> &str {
        self.info.get(key).map(String::as_str).unwrap_or("")
    }

    fn available(&self) -> bool {
        !self.get("newest").is_empty() && self.get("newest") != self.get("installed") && self.get("live").is_empty()
    }

    fn start(&mut self, ctx: &egui::Context) {
        let password = self.need_password.then(|| format!("{}\n", self.password));
        self.running = true;
        self.password_error = false;
        self.log.clear();
        self.step = 0;
        self.progress = None;
        self.updated = false;
        self.result = None;
        let (tx, ctx) = (self.tx.clone(), ctx.clone());
        thread::spawn(move || {
            // a wrong password: ask again instead of failing the update
            // (-k: sudo reads the password even if it remembers an earlier one)
            if let Some(pw) = &password {
                let ok = Command::new("sudo")
                    .args(["-k", "-S", "-p", "", "true"])
                    .stdin(Stdio::piped())
                    .stderr(Stdio::null())
                    .spawn()
                    .and_then(|mut c| {
                        let _ = c.stdin.take().unwrap().write_all(pw.as_bytes());
                        c.wait()
                    })
                    .is_ok_and(|s| s.success());
                if !ok {
                    let _ = tx.send(Msg::BadPassword);
                    ctx.request_repaint();
                    return;
                }
            }
            let mut cmd = Command::new("sudo");
            cmd.args(["-k", "-S", "-p", "", "--", "mlpkg", "system-update", "-y"])
                .env("LC_ALL", "C")
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped());
            let mut child = match cmd.spawn() {
                Ok(c) => c,
                Err(e) => {
                    let _ = tx.send(Msg::Line(format!("cannot start mlpkg: {e}")));
                    let _ = tx.send(Msg::Exit(false));
                    ctx.request_repaint();
                    return;
                }
            };
            if let (Some(mut stdin), Some(pw)) = (child.stdin.take(), &password) {
                let _ = stdin.write_all(pw.as_bytes());
            }
            let readers = [
                {
                    let (s, tx, ctx) = (child.stdout.take().unwrap(), tx.clone(), ctx.clone());
                    thread::spawn(move || forward(s, tx, ctx))
                },
                {
                    let (s, tx, ctx) = (child.stderr.take().unwrap(), tx.clone(), ctx.clone());
                    thread::spawn(move || forward(s, tx, ctx))
                },
            ];
            for r in readers {
                let _ = r.join();
            }
            let ok = child.wait().is_ok_and(|s| s.success());
            let _ = tx.send(Msg::Exit(ok));
            ctx.request_repaint();
        });
    }

    fn poll(&mut self) {
        while let Ok(m) = self.rx.try_recv() {
            match m {
                Msg::Info(r, need_password) => {
                    self.need_password = need_password;
                    self.focus_password = need_password;
                    match r {
                        Ok(i) => {
                            self.info = i;
                            self.error = None;
                        }
                        Err(e) => self.error = Some(e),
                    }
                    self.page = Page::Details;
                }
                Msg::BadPassword => {
                    self.running = false;
                    self.password_error = true;
                    self.focus_password = true;
                    self.password.clear();
                }
                Msg::Line(l) => {
                    self.page = Page::Update;
                    if let Some(s) = l.strip_prefix("==> ") {
                        if let Some(i) = STEPS.iter().position(|(k, _)| s.starts_with(k)) {
                            self.step = i + 1;
                        }
                    }
                    if l.starts_with("MicroLinux is updated to build") {
                        self.updated = true;
                    }
                    self.log.push(l);
                }
                Msg::Progress(p) => {
                    self.page = Page::Update;
                    self.progress = Some(p);
                }
                Msg::Exit(ok) => {
                    self.page = Page::Update;
                    self.running = false;
                    self.result = Some(ok);
                }
            }
        }
    }

    // --- pages -------------------------------------------------------------

    fn details_page(&mut self, ui: &mut egui::Ui) {
        if let Some(e) = &self.error {
            ui.heading(RichText::new("Could not check for updates").color(RED));
            ui.add_space(8.0);
            ui.label(e);
            return;
        }
        let version = |v: &str| if v.is_empty() { "MicroLinux".to_string() } else { format!("MicroLinux {v}") };
        let available = self.available();
        if !self.get("live").is_empty() {
            ui.heading("This is the live system");
        } else if available {
            ui.heading(format!("{} is available", version(self.get("newest_version"))));
        } else {
            ui.heading("MicroLinux is up to date");
        }
        ui.add_space(8.0);
        egui::Grid::new("versions").spacing([16.0, 6.0]).show(ui, |ui| {
            ui.label("");
            ui.label(RichText::new("Version").strong());
            ui.label(RichText::new("Build").strong());
            ui.end_row();
            ui.label("Installed:");
            ui.label(self.get("installed_version"));
            ui.label(RichText::new(self.get("installed")).monospace());
            ui.end_row();
            ui.label("Newest:");
            ui.label(if self.get("newest_version").is_empty() { "unknown" } else { self.get("newest_version") });
            ui.label(RichText::new(self.get("newest")).monospace());
            ui.end_row();
        });
        ui.add_space(10.0);
        if !self.get("live").is_empty() {
            ui.label("The live system can't update itself. Download the newest ISO from github.com/praneethashok14/microlinux/releases and write it to the USB stick, or install MicroLinux to a disk.");
            return;
        }
        if !available {
            ui.label("There is nothing to update.");
            return;
        }
        let small = self.get("download").starts_with("update-");
        let size = megabytes(self.get("download_bytes"));
        ui.label(RichText::new("What happens").strong());
        for t in [
            match (small, size) {
                (true, Some(s)) => format!("Only the files that changed since your version are downloaded ({s})."),
                (true, None) => "Only the files that changed since your version are downloaded.".into(),
                (false, Some(s)) => format!("The new system is downloaded ({s})."),
                (false, None) => "The new system is downloaded (about 300 MB).".into(),
            },
            "The system files, the kernel and the boot loader are replaced, then the installed packages are updated.".into(),
            "Your files, settings, passwords and installed packages are kept.".into(),
            "Restart the computer afterwards to start the new version.".into(),
        ] {
            ui.label(format!("  •  {t}"));
        }
        if !self.get("battery_low").is_empty() {
            ui.add_space(8.0);
            ui.colored_label(RED, format!("The battery is at {}%: plug in the charger before updating.", self.get("battery_low")));
        }
        if self.need_password {
            ui.add_space(12.0);
            ui.horizontal(|ui| {
                ui.label("Your password:");
                let r = ui.add_enabled(
                    !self.running,
                    egui::TextEdit::singleline(&mut self.password).password(true).desired_width(220.0),
                );
                if std::mem::take(&mut self.focus_password) {
                    r.request_focus();
                }
                if r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) && !self.password.is_empty() {
                    self.start(ui.ctx());
                }
                if self.running {
                    ui.spinner();
                }
            });
            if self.password_error {
                ui.colored_label(RED, "Wrong password, try again.");
            } else {
                ui.label(RichText::new("Updating needs administrator rights.").small().color(Color32::GRAY));
            }
        }
    }

    fn update_page(&mut self, ui: &mut egui::Ui) {
        let to = self.get("newest_version").to_string();
        match self.result {
            None => ui.heading("Updating MicroLinux…"),
            Some(_) if self.updated => ui.heading(format!("MicroLinux {to} is installed").replace("  ", " ")),
            Some(true) => ui.heading("MicroLinux is up to date"),
            Some(false) => ui.heading(RichText::new("The update failed").color(RED)),
        };
        ui.add_space(8.0);
        // the download counts by its progress; the other steps as one each
        let frac = match self.result {
            Some(true) => 1.0,
            _ if self.step == 0 => 0.0,
            _ => {
                let part = if self.step == 2 { self.progress.unwrap_or(0.0) / 100.0 } else { 0.5 };
                (self.step as f32 - 1.0 + part) / STEPS.len() as f32
            }
        };
        ui.add(egui::ProgressBar::new(frac).show_percentage().animate(self.result.is_none()));
        ui.add_space(6.0);
        for (i, (_, name)) in STEPS.iter().enumerate() {
            let n = i + 1;
            let done = n < self.step || (n == self.step && self.result == Some(true));
            let (mark, color) = if done {
                ("✔", GREEN)
            } else if n == self.step {
                if self.result == Some(false) { ("✖", RED) } else { ("▶", ui.visuals().text_color()) }
            } else {
                ("  ", Color32::GRAY)
            };
            let mut text = format!("{mark}  {name}");
            if n == 2 && n == self.step && self.result.is_none() {
                if let Some(p) = self.progress {
                    text += &format!("  ({p:.0}%)");
                }
            }
            ui.colored_label(color, text);
        }
        ui.add_space(8.0);
        match self.result {
            Some(_) if self.updated => {
                if self.result == Some(false) {
                    ui.label("The system is updated, but updating the installed packages failed (see Details); they are updated the next time.");
                }
                ui.label(RichText::new("Restart the computer to start the new version.").strong());
            }
            Some(false) => {
                let why = self
                    .log
                    .iter()
                    .rev()
                    .find_map(|l| l.strip_prefix("mlpkg system-update: "))
                    .unwrap_or("see Details below");
                ui.label(format!("The installed system was not changed: {why}"));
            }
            _ => {}
        }
        ui.add_space(8.0);
        let open = self.result == Some(false) && !self.updated;
        egui::CollapsingHeader::new("Details").default_open(open).show(ui, |ui| {
            egui::ScrollArea::vertical().max_height(160.0).stick_to_bottom(true).show(ui, |ui| {
                for l in &self.log {
                    ui.label(RichText::new(l).monospace().small());
                }
            });
        });
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.poll();
        let busy = self.running && self.page == Page::Update;
        if ctx.input(|i| i.viewport().close_requested()) && busy {
            ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
        }

        egui::TopBottomPanel::top("title").show(ctx, |ui| {
            ui.add_space(6.0);
            ui.label(RichText::new("System Update").strong().size(17.0));
            ui.add_space(4.0);
        });

        egui::TopBottomPanel::bottom("buttons").show(ctx, |ui| {
            ui.add_space(6.0);
            ui.horizontal(|ui| {
                if busy {
                    ui.label(RichText::new("Do not switch off the computer.").color(Color32::GRAY));
                }
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| match self.page {
                    Page::Checking => {
                        if ui.button("Cancel").clicked() {
                            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                        }
                    }
                    Page::Details => {
                        if self.available() && self.error.is_none() {
                            let ready = !self.running && (!self.need_password || !self.password.is_empty());
                            if ui.add_enabled(ready, egui::Button::new(RichText::new("Update").strong())).clicked() {
                                self.start(ctx);
                            }
                        } else if ui.button("Check again").clicked() {
                            self.check(ctx);
                        }
                        if ui.add_enabled(!self.running, egui::Button::new("Close")).clicked() {
                            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                        }
                    }
                    Page::Update => {
                        if self.updated && !busy && ui.button(RichText::new("Restart now").strong()).clicked() {
                            let _ = Command::new("sudo").args(["-n", "/usr/sbin/reboot"]).spawn();
                        }
                        if !busy && ui.button(if self.updated { "Restart later" } else { "Close" }).clicked() {
                            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                        }
                    }
                });
            });
            ui.add_space(4.0);
        });

        egui::CentralPanel::default().show(ctx, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| match self.page {
                Page::Checking => {
                    ui.horizontal(|ui| {
                        ui.spinner();
                        ui.label("Checking for updates…");
                    });
                }
                Page::Details => self.details_page(ui),
                Page::Update => self.update_page(ui),
            });
        });
    }
}

pub fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("System Update")
            .with_app_id("ml-updater")
            .with_inner_size([620.0, 480.0])
            .with_min_inner_size([480.0, 380.0]),
        renderer: eframe::Renderer::Glow,
        ..Default::default()
    };
    eframe::run_native("System Update", options, Box::new(|cc| Ok(Box::new(App::new(cc)))))
}
