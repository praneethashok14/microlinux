//! ml-installer: the graphical MicroLinux installer.
//!
//! It only asks the questions and shows the progress. The installation itself
//! is done by ml-install (run through sudo), the same script the command line
//! installer and the automated tests use:
//!   sudo ml-install --probe DISK        facts about a disk, as key=value lines
//!   sudo ml-install -y --passwords-stdin --hostname NAME [--alongside] DISK

use eframe::egui::{self, Color32, RichText};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;

/// ml-install's "==> " progress lines, in order
const STEPS: [(&str, &str); 6] = [
    ("partitioning", "Partitioning the disk"),
    ("creating filesystems", "Creating file systems"),
    ("copying system", "Copying the system"),
    ("copying packages", "Copying the packages"),
    ("installing boot loader", "Installing the boot loader"),
    ("configuring", "Configuring"),
];
/// ml-install needs this much (whole disk, or free space for dual boot)
const MIN_MIB: u64 = 2048;
const RED: Color32 = Color32::from_rgb(0xc0, 0x1c, 0x28);
const GREEN: Color32 = Color32::from_rgb(0x26, 0xa2, 0x69);

#[derive(Clone, Copy, PartialEq)]
enum Page {
    Welcome,
    Disk,
    Account,
    Summary,
    Install,
}

#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Erase,
    Alongside,
}

struct Disk {
    path: String,
    size: u64,
    model: String,
    tran: String,
}

#[derive(Clone, Default)]
struct Part {
    name: String,
    size: u64,
    fstype: String,
    label: String,
}

#[derive(Clone, Default)]
struct Probe {
    size_mib: u64,
    uefi: bool,
    gpt: bool,
    free_mib: u64,
    esp: String,
    bitlocker: bool,
    parts: Vec<Part>,
}

impl Probe {
    /// why installing alongside the existing partitions isn't possible, if it isn't
    fn alongside_problem(&self) -> Option<String> {
        if self.parts.is_empty() {
            Some("the disk is empty".into())
        } else if !self.uefi {
            Some("the live system was started in BIOS (Legacy/CSM) mode, not UEFI".into())
        } else if !self.gpt {
            Some("the disk uses an MBR partition table, not GPT".into())
        } else if self.free_mib < MIN_MIB {
            Some(format!(
                "only {} of free space (needs {}): shrink a partition first, e.g. Windows Disk Management > Shrink Volume",
                mib(self.free_mib),
                mib(MIN_MIB)
            ))
        } else {
            None
        }
    }
}

enum Msg {
    Line(String),
    Exit(bool),
}

struct App {
    page: Page,
    release: String,
    live: bool,
    disks: Vec<Disk>,
    disk_error: Option<String>,
    probes: HashMap<String, Result<Probe, String>>,
    probe_tx: Sender<(String, Result<Probe, String>)>,
    probe_rx: Receiver<(String, Result<Probe, String>)>,
    selected: Option<String>,
    mode: Mode,
    hostname: String,
    user_pw: [String; 2],
    root_same: bool,
    root_pw: [String; 2],
    confirm: bool,
    /// put the cursor into the password field when the page opens
    focus_password: bool,
    log: Vec<String>,
    step: usize,
    install_rx: Option<Receiver<Msg>>,
    result: Option<bool>,
}

fn mib(m: u64) -> String {
    if m >= 1024 * 10 {
        format!("{} GB", m * 1048576 / 1_000_000_000)
    } else if m >= 1024 {
        format!("{:.1} GB", m as f64 * 1048576.0 / 1e9)
    } else {
        format!("{m} MB")
    }
}

/// lsblk -P output: KEY="VALUE" pairs, special characters escaped as \xNN
fn lsblk_pairs(line: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    let mut rest = line.trim();
    while let Some(eq) = rest.find("=\"") {
        let key = rest[..eq].trim().to_string();
        let after = &rest[eq + 2..];
        let end = after.find('"').unwrap_or(after.len());
        map.insert(key, unescape(&after[..end]));
        rest = after.get(end + 1..).unwrap_or("");
    }
    map
}

fn unescape(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'\\' && i + 3 < b.len() && b[i + 1] == b'x' {
            if let Ok(v) = u8::from_str_radix(&s[i + 2..i + 4], 16) {
                out.push(v);
                i += 4;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn list_disks() -> Result<Vec<Disk>, String> {
    let out = Command::new("lsblk")
        .args(["-nbdpP", "-o", "NAME,SIZE,MODEL,TRAN,TYPE"])
        .output()
        .map_err(|e| format!("lsblk: {e}"))?;
    let mut disks = Vec::new();
    for line in String::from_utf8_lossy(&out.stdout).lines() {
        let p = lsblk_pairs(line);
        let path = p.get("NAME").cloned().unwrap_or_default();
        if p.get("TYPE").map(String::as_str) != Some("disk")
            || ["/dev/loop", "/dev/zram", "/dev/sr", "/dev/ram"].iter().any(|x| path.starts_with(x))
        {
            continue;
        }
        disks.push(Disk {
            size: p.get("SIZE").and_then(|s| s.parse().ok()).unwrap_or(0),
            model: p.get("MODEL").cloned().unwrap_or_default().trim().to_string(),
            tran: p.get("TRAN").cloned().unwrap_or_default(),
            path,
        });
    }
    Ok(disks)
}

fn probe(disk: &str) -> Result<Probe, String> {
    let out = Command::new("sudo")
        .args(["-n", "ml-install", "--probe", disk])
        .output()
        .map_err(|e| format!("sudo: {e}"))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(err.trim().trim_start_matches("ml-install: ").to_string());
    }
    let mut p = Probe::default();
    for line in String::from_utf8_lossy(&out.stdout).lines() {
        let Some((k, v)) = line.split_once('=') else { continue };
        match k {
            "size_mib" => p.size_mib = v.parse().unwrap_or(0),
            "uefi" => p.uefi = v == "1",
            "gpt" => p.gpt = v == "1",
            "free_mib" => p.free_mib = v.parse().unwrap_or(0),
            "esp" => p.esp = v.to_string(),
            "bitlocker" => p.bitlocker = v == "1",
            "part" => {
                let m = lsblk_pairs(v);
                p.parts.push(Part {
                    name: m.get("NAME").cloned().unwrap_or_default(),
                    size: m.get("SIZE").and_then(|s| s.parse().ok()).unwrap_or(0),
                    fstype: m.get("FSTYPE").cloned().unwrap_or_default(),
                    label: m.get("LABEL").cloned().unwrap_or_default(),
                });
            }
            _ => {}
        }
    }
    Ok(p)
}

fn hostname_ok(h: &str) -> bool {
    !h.is_empty()
        && h.len() <= 63
        && !h.starts_with('-')
        && !h.ends_with('-')
        && h.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// None if the two entries are a usable password, else what is wrong
fn password_problem(pw: &[String; 2]) -> Option<&'static str> {
    if pw[0].is_empty() {
        Some("enter a password")
    } else if pw[0].contains(':') || pw[0].contains('\n') {
        Some("the password must not contain ':'")
    } else if pw[0] != pw[1] {
        Some("the two passwords are different")
    } else {
        None
    }
}

impl App {
    fn new(cc: &eframe::CreationContext) -> Self {
        cc.egui_ctx.set_theme(egui::Theme::Light);
        cc.egui_ctx.set_zoom_factor(1.15);
        let (probe_tx, probe_rx) = channel();
        App {
            page: Page::Welcome,
            release: std::fs::read_to_string("/etc/microlinux-release")
                .map(|s| s.trim().to_string())
                .unwrap_or_default(),
            live: std::path::Path::new("/live/rootfs/usr").is_dir(),
            disks: Vec::new(),
            disk_error: None,
            probes: HashMap::new(),
            probe_tx,
            probe_rx,
            selected: None,
            mode: Mode::Erase,
            hostname: "microlinux".into(),
            user_pw: Default::default(),
            root_same: true,
            root_pw: Default::default(),
            confirm: false,
            focus_password: false,
            log: Vec::new(),
            step: 0,
            install_rx: None,
            result: None,
        }
    }

    fn refresh_disks(&mut self, ctx: &egui::Context) {
        self.probes.clear();
        self.selected = None;
        match list_disks() {
            Ok(d) => {
                self.disks = d;
                self.disk_error = None;
            }
            Err(e) => self.disk_error = Some(e),
        }
        for d in &self.disks {
            let (tx, path, ctx) = (self.probe_tx.clone(), d.path.clone(), ctx.clone());
            thread::spawn(move || {
                let r = probe(&path);
                let _ = tx.send((path, r));
                ctx.request_repaint();
            });
        }
    }

    fn selected_probe(&self) -> Option<&Probe> {
        self.selected.as_ref().and_then(|s| self.probes.get(s)).and_then(|r| r.as_ref().ok())
    }

    fn select(&mut self, path: &str) {
        self.selected = Some(path.to_string());
        self.confirm = false;
        // keep what is on the disk when that is possible
        self.mode = match self.selected_probe() {
            Some(p) if p.alongside_problem().is_none() => Mode::Alongside,
            _ => Mode::Erase,
        };
    }

    fn can_continue(&self) -> bool {
        match self.page {
            Page::Welcome => self.live,
            Page::Disk => match self.selected_probe() {
                Some(p) => self.mode == Mode::Erase || p.alongside_problem().is_none(),
                None => false,
            },
            Page::Account => {
                hostname_ok(&self.hostname)
                    && password_problem(&self.user_pw).is_none()
                    && (self.root_same || password_problem(&self.root_pw).is_none())
            }
            Page::Summary => self.confirm,
            Page::Install => false,
        }
    }

    fn start_install(&mut self, ctx: &egui::Context) {
        let disk = self.selected.clone().unwrap_or_default();
        let root = if self.root_same { &self.user_pw[0] } else { &self.root_pw[0] };
        let passwords = format!("root:{}\nuser:{}\n", root, self.user_pw[0]);
        let mut cmd = Command::new("sudo");
        cmd.args(["-n", "ml-install", "-y", "--passwords-stdin", "--hostname", &self.hostname]);
        if self.mode == Mode::Alongside {
            cmd.arg("--alongside");
        }
        cmd.arg(&disk).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
        let (tx, rx) = channel();
        self.install_rx = Some(rx);
        self.log.clear();
        self.step = 0;
        self.result = None;
        let ctx = ctx.clone();
        thread::spawn(move || {
            let mut child = match cmd.spawn() {
                Ok(c) => c,
                Err(e) => {
                    let _ = tx.send(Msg::Line(format!("cannot start ml-install: {e}")));
                    let _ = tx.send(Msg::Exit(false));
                    ctx.request_repaint();
                    return;
                }
            };
            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(passwords.as_bytes());
            }
            let mut readers = Vec::new();
            let streams: [Box<dyn std::io::Read + Send>; 2] = [
                Box::new(child.stdout.take().unwrap()),
                Box::new(child.stderr.take().unwrap()),
            ];
            for stream in streams {
                let (tx, ctx) = (tx.clone(), ctx.clone());
                readers.push(thread::spawn(move || {
                    for line in BufReader::new(stream).lines().map_while(Result::ok) {
                        let _ = tx.send(Msg::Line(line));
                        ctx.request_repaint();
                    }
                }));
            }
            for r in readers {
                let _ = r.join();
            }
            let ok = child.wait().map(|s| s.success()).unwrap_or(false);
            let _ = tx.send(Msg::Exit(ok));
            ctx.request_repaint();
        });
    }

    fn poll(&mut self) {
        while let Ok((path, r)) = self.probe_rx.try_recv() {
            self.probes.insert(path.clone(), r);
            if self.selected.as_deref() == Some(path.as_str()) {
                self.select(&path);
            }
        }
        if let Some(rx) = &self.install_rx {
            while let Ok(m) = rx.try_recv() {
                match m {
                    Msg::Line(l) => {
                        if let Some(s) = l.strip_prefix("==> ") {
                            if let Some(i) = STEPS.iter().position(|(k, _)| s.starts_with(k)) {
                                self.step = i + 1;
                            }
                        }
                        self.log.push(l);
                    }
                    Msg::Exit(ok) => self.result = Some(ok),
                }
            }
        }
    }

    // --- pages -------------------------------------------------------------

    fn welcome(&mut self, ui: &mut egui::Ui) {
        ui.heading(format!("Welcome to MicroLinux {}", self.release));
        ui.add_space(8.0);
        ui.label("This installs MicroLinux from the live system onto a disk of this computer:");
        ui.add_space(4.0);
        for t in [
            "on a disk of its own (everything on that disk is erased), or",
            "next to Windows or another system that is already on the disk (dual boot).",
        ] {
            ui.label(format!("  •  {t}"));
        }
        ui.add_space(8.0);
        ui.label("The installed system is the one you are using now, with Firefox and the other packages of the live medium. It needs a disk with at least 2 GB of space; installing takes a few minutes.");
        ui.add_space(8.0);
        ui.label(RichText::new("Back up your files before you continue.").strong());
        if !self.live {
            ui.add_space(12.0);
            ui.colored_label(RED, "The installer works only in the MicroLinux live system (started from the USB stick or DVD).");
        }
    }

    fn disk_page(&mut self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            ui.heading("Where should MicroLinux go?");
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("⟳ Refresh").clicked() {
                    self.refresh_disks(ui.ctx());
                }
            });
        });
        ui.add_space(6.0);
        if let Some(e) = &self.disk_error {
            ui.colored_label(RED, e);
        }
        if self.disks.is_empty() && self.disk_error.is_none() {
            ui.label("No disks found.");
        }
        let mut clicked = None;
        for d in &self.disks {
            let probe = self.probes.get(&d.path);
            let usable = matches!(probe, Some(Ok(_)));
            let mut text = format!("{}   {}", d.path, mib(d.size / 1048576));
            if !d.model.is_empty() {
                text += &format!("   {}", d.model);
            }
            if d.tran == "usb" {
                text += "   (USB)";
            }
            let sel = self.selected.as_deref() == Some(d.path.as_str());
            ui.add_enabled_ui(usable, |ui| {
                let r = ui.add_sized([ui.available_width(), 28.0], egui::Button::selectable(sel, RichText::new(text).size(15.0)));
                if r.clicked() {
                    clicked = Some(d.path.clone());
                }
            });
            match probe {
                None => {
                    ui.horizontal(|ui| {
                        ui.spinner();
                        ui.label("checking…");
                    });
                }
                Some(Err(e)) => {
                    ui.label(RichText::new(format!("    not usable: {e}")).small().color(Color32::GRAY));
                }
                _ => {}
            }
        }
        if let Some(p) = clicked {
            self.select(&p);
        }
        let Some(p) = self.selected_probe().cloned() else { return };
        ui.add_space(10.0);
        ui.separator();
        if p.parts.is_empty() {
            ui.label("The disk has no partitions.");
        } else {
            ui.label(RichText::new("On this disk now:").strong());
            egui::Grid::new("parts").striped(true).spacing([18.0, 4.0]).show(ui, |ui| {
                for part in &p.parts {
                    ui.label(&part.name);
                    ui.label(mib(part.size / 1048576));
                    ui.label(if part.fstype.is_empty() { "-" } else { &part.fstype });
                    ui.label(&part.label);
                    ui.end_row();
                }
            });
            ui.label(format!("Free space: {}", mib(p.free_mib)));
        }
        ui.add_space(8.0);
        let along = p.alongside_problem();
        ui.add_enabled_ui(along.is_none(), |ui| {
            ui.radio_value(&mut self.mode, Mode::Alongside, "Install alongside the existing systems (dual boot, keeps all partitions)");
        });
        if let Some(why) = along {
            if !p.parts.is_empty() {
                ui.label(RichText::new(format!("      not possible: {why}")).small().color(Color32::GRAY));
            }
        }
        ui.radio_value(&mut self.mode, Mode::Erase, "Erase the whole disk and install MicroLinux on it");
    }

    fn account_page(&mut self, ui: &mut egui::Ui) {
        ui.heading("Computer name and passwords");
        ui.add_space(8.0);
        egui::Grid::new("account").spacing([12.0, 8.0]).show(ui, |ui| {
            ui.label("Computer name:");
            ui.add(egui::TextEdit::singleline(&mut self.hostname).desired_width(240.0));
            ui.end_row();
            ui.label("");
            if hostname_ok(&self.hostname) {
                ui.label(RichText::new("lower-case letters, digits and '-'").small().color(Color32::GRAY));
            } else {
                ui.colored_label(RED, "use lower-case letters, digits and '-' (not first or last)");
            }
            ui.end_row();
            ui.label("Password for 'user':");
            let r = ui.add(egui::TextEdit::singleline(&mut self.user_pw[0]).password(true).desired_width(240.0));
            if std::mem::take(&mut self.focus_password) {
                r.request_focus();
            }
            ui.end_row();
            ui.label("Repeat it:");
            ui.add(egui::TextEdit::singleline(&mut self.user_pw[1]).password(true).desired_width(240.0));
            ui.end_row();
            ui.label("");
            match password_problem(&self.user_pw) {
                Some(p) => ui.colored_label(RED, p),
                None => ui.colored_label(GREEN, "✔"),
            };
            ui.end_row();
        });
        ui.add_space(6.0);
        ui.checkbox(&mut self.root_same, "Use the same password for the administrator (root)");
        if !self.root_same {
            egui::Grid::new("root").spacing([12.0, 8.0]).show(ui, |ui| {
                ui.label("Password for 'root':");
                ui.add(egui::TextEdit::singleline(&mut self.root_pw[0]).password(true).desired_width(240.0));
                ui.end_row();
                ui.label("Repeat it:");
                ui.add(egui::TextEdit::singleline(&mut self.root_pw[1]).password(true).desired_width(240.0));
                ui.end_row();
                ui.label("");
                match password_problem(&self.root_pw) {
                    Some(p) => ui.colored_label(RED, p),
                    None => ui.colored_label(GREEN, "✔"),
                };
                ui.end_row();
            });
        }
        ui.add_space(10.0);
        ui.label(RichText::new("The installed system starts the desktop without asking; the password is needed for sudo, after logging out and when the screen is locked.").small());
    }

    fn summary_page(&mut self, ui: &mut egui::Ui) {
        let disk = self.selected.clone().unwrap_or_default();
        let Some(p) = self.selected_probe().cloned() else { return };
        ui.heading("Ready to install");
        ui.add_space(8.0);
        egui::Grid::new("summary").spacing([12.0, 6.0]).show(ui, |ui| {
            ui.label("Disk:");
            ui.label(format!("{disk} ({})", mib(p.size_mib)));
            ui.end_row();
            ui.label("Computer name:");
            ui.label(&self.hostname);
            ui.end_row();
            ui.label("Users:");
            ui.label("user (desktop), root (administrator)");
            ui.end_row();
        });
        ui.add_space(10.0);
        match self.mode {
            Mode::Erase => {
                let firmware = if cfg!(target_arch = "x86_64") { " It starts on UEFI and BIOS computers." } else { "" };
                ui.label(format!("The disk gets a new GPT partition table: a 256 MB EFI system partition and the MicroLinux system in the rest.{firmware}"));
                ui.add_space(8.0);
                if !p.parts.is_empty() {
                    ui.colored_label(RED, RichText::new("These partitions and everything on them will be deleted:").strong());
                    for part in &p.parts {
                        ui.colored_label(RED, format!("    {}  {}  {} {}", part.name, mib(part.size / 1048576), part.fstype, part.label));
                    }
                    ui.add_space(6.0);
                }
                ui.checkbox(&mut self.confirm, RichText::new(format!("Erase everything on {disk}")).strong());
            }
            Mode::Alongside => {
                ui.label(format!("All {} existing partitions are kept. MicroLinux goes into the free space ({}).", p.parts.len(), mib(p.free_mib)));
                if p.esp.is_empty() {
                    ui.label("Boot loader: a new 256 MB EFI system partition in the free space.");
                } else {
                    ui.label(format!("Boot loader: EFI/microlinux on the existing EFI system partition {}.", p.esp));
                }
                ui.label("After restarting, a menu offers MicroLinux and Windows; the firmware boot menu has both too.");
                if p.bitlocker {
                    ui.add_space(6.0);
                    ui.colored_label(RED, "Windows uses BitLocker (device encryption). Have the recovery key at hand: Windows may ask for it once after this (account.microsoft.com/devices/recoverykey).");
                }
                ui.add_space(8.0);
                ui.checkbox(&mut self.confirm, RichText::new(format!("Install MicroLinux on {disk}")).strong());
            }
        }
    }

    fn install_page(&mut self, ui: &mut egui::Ui) {
        match self.result {
            None => ui.heading("Installing MicroLinux…"),
            Some(true) => ui.heading("MicroLinux is installed"),
            Some(false) => ui.heading(RichText::new("The installation failed").color(RED)),
        };
        ui.add_space(8.0);
        let frac = match self.result {
            Some(true) => 1.0,
            _ if self.step == 0 => 0.0,
            _ => (self.step as f32 - 0.5) / STEPS.len() as f32,
        };
        ui.add(egui::ProgressBar::new(frac).show_percentage().animate(self.result.is_none()));
        ui.add_space(6.0);
        for (i, (_, name)) in STEPS.iter().enumerate() {
            let n = i + 1;
            let (mark, color) = if n < self.step || (n == self.step && self.result == Some(true)) {
                ("✔", GREEN)
            } else if n == self.step {
                if self.result == Some(false) { ("✖", RED) } else { ("▶", ui.visuals().text_color()) }
            } else {
                ("  ", Color32::GRAY)
            };
            ui.colored_label(color, format!("{mark}  {name}"));
        }
        match self.result {
            Some(true) => {
                ui.add_space(8.0);
                let text = if self.mode == Mode::Alongside {
                    "Remove the USB stick or DVD and restart. MicroLinux starts first, with Windows in its menu."
                } else {
                    "Remove the USB stick or DVD and restart to start MicroLinux from the disk."
                };
                ui.label(RichText::new(text).strong());
            }
            Some(false) => {
                ui.add_space(8.0);
                ui.label("Nothing was changed outside the chosen disk. The messages below say what went wrong.");
            }
            None => {}
        }
        ui.add_space(8.0);
        let open = self.result == Some(false);
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
        let busy = self.install_rx.is_some() && self.result.is_none();
        if ctx.input(|i| i.viewport().close_requested()) && busy {
            ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
        }

        egui::TopBottomPanel::top("steps").show(ctx, |ui| {
            ui.add_space(6.0);
            ui.horizontal(|ui| {
                ui.label(RichText::new("Install MicroLinux").strong().size(17.0));
                ui.add_space(16.0);
                for (p, name) in [
                    (Page::Welcome, "Welcome"),
                    (Page::Disk, "Disk"),
                    (Page::Account, "Users"),
                    (Page::Summary, "Summary"),
                    (Page::Install, "Install"),
                ] {
                    let t = RichText::new(name);
                    ui.label(if p == self.page { t.strong().underline() } else { t.color(Color32::GRAY) });
                }
            });
            ui.add_space(4.0);
        });

        egui::TopBottomPanel::bottom("buttons").show(ctx, |ui| {
            ui.add_space(6.0);
            ui.horizontal(|ui| {
                if self.page == Page::Install {
                    if busy {
                        ui.label(RichText::new("Do not switch off the computer.").color(Color32::GRAY));
                    }
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if self.result == Some(true) && ui.button(RichText::new("Restart now").strong()).clicked() {
                            let _ = Command::new("sudo").args(["-n", "reboot"]).spawn();
                        }
                        if !busy && ui.button("Close").clicked() {
                            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                        }
                    });
                    return;
                }
                if self.page != Page::Welcome && ui.button("Back").clicked() {
                    self.page = match self.page {
                        Page::Disk => Page::Welcome,
                        Page::Account => Page::Disk,
                        _ => Page::Account,
                    };
                }
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let label = if self.page == Page::Summary { "Install" } else { "Next" };
                    let next = ui.add_enabled(self.can_continue(), egui::Button::new(RichText::new(label).strong()));
                    if next.clicked() {
                        self.page = match self.page {
                            Page::Welcome => {
                                self.refresh_disks(ctx);
                                Page::Disk
                            }
                            Page::Disk => {
                                self.focus_password = true;
                                Page::Account
                            }
                            Page::Account => {
                                self.confirm = false;
                                Page::Summary
                            }
                            _ => {
                                self.start_install(ctx);
                                Page::Install
                            }
                        };
                    }
                    if ui.button("Quit").clicked() {
                        ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                    }
                });
            });
            ui.add_space(4.0);
        });

        egui::CentralPanel::default().show(ctx, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| match self.page {
                Page::Welcome => self.welcome(ui),
                Page::Disk => self.disk_page(ui),
                Page::Account => self.account_page(ui),
                Page::Summary => self.summary_page(ui),
                Page::Install => self.install_page(ui),
            });
        });
    }
}

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("Install MicroLinux")
            .with_app_id("ml-installer")
            .with_inner_size([760.0, 580.0])
            .with_min_inner_size([560.0, 440.0]),
        renderer: eframe::Renderer::Glow,
        ..Default::default()
    };
    eframe::run_native("Install MicroLinux", options, Box::new(|cc| Ok(Box::new(App::new(cc)))))
}
