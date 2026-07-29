//! Deniable whole-zone VMs (Shufflecake layers): CRUD + unlock/lock = show/hide.
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph},
    Frame, Terminal,
};
use serde_json::{json, Map, Value};
use std::{
    env, fs, io,
    io::{Write as IoWrite, Stdout},
    path::PathBuf,
    process::{Command, Stdio},
};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Screen {
    List,
    Edit,
    Help,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum InputKind {
    None,
    AddName,
    UnlockPass,
    ConfirmDelete,
}

const TEMPLATES: &[&str] = &["desktop", "dev", "browser", "radio"];
const COLORS: &[&str] = &[
    "red", "orange", "yellow", "green", "blue", "purple", "black", "gray",
];
const NET_MODES: &[&str] = &["nym", "i2p", "tor", "none"];

struct App {
    path: PathBuf,
    zones: Map<String, Value>,
    names: Vec<String>,
    list: ListState,
    screen: Screen,
    status: String,
    dirty: bool,
    input: String,
    input_kind: InputKind,
    unlock_layer: u64,
}

impl App {
    fn load(path: PathBuf) -> io::Result<Self> {
        let raw = if path.is_file() {
            fs::read_to_string(&path)?
        } else {
            "{}\n".into()
        };
        let v: Value = serde_json::from_str(&raw)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let zones = v.as_object().cloned().unwrap_or_default();
        let mut names: Vec<_> = zones.keys().cloned().collect();
        names.sort();
        let mut list = ListState::default();
        if !names.is_empty() {
            list.select(Some(0));
        }
        Ok(Self {
            path,
            zones,
            names,
            list,
            screen: Screen::List,
            status: "Hidden whole VMs on Shufflecake layers. Unlock = show in GNOME.".into(),
            dirty: false,
            input: String::new(),
            input_kind: InputKind::None,
            unlock_layer: 1,
        })
    }

    fn refresh(&mut self) {
        let sel = self.selected().map(|s| s.to_string());
        self.names = self.zones.keys().cloned().collect();
        self.names.sort();
        if let Some(n) = sel {
            if let Some(i) = self.names.iter().position(|x| x == &n) {
                self.list.select(Some(i));
                return;
            }
        }
        if self.names.is_empty() {
            self.list.select(None);
        } else {
            self.list.select(Some(0));
        }
    }

    fn selected(&self) -> Option<&str> {
        self.list.selected().map(|i| self.names[i].as_str())
    }

    fn save(&mut self) -> io::Result<()> {
        let pretty = serde_json::to_string_pretty(&Value::Object(self.zones.clone()))
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let bak = self.path.with_extension("json.bak");
        let _ = fs::copy(&self.path, &bak);
        fs::write(&self.path, pretty + "\n")?;
        self.dirty = false;
        self.status = format!(
            "Saved {}. Rebuild guests: sudo nixos-rebuild switch --flake .#host",
            self.path.display()
        );
        let _ = Command::new("bunker-sflc").arg("sync-visible").status();
        Ok(())
    }

    fn next_free(&self) -> (String, String, u64) {
        let mut used_ip = std::collections::HashSet::new();
        let mut used_socks = std::collections::HashSet::new();
        let mut used_mac = std::collections::HashSet::new();
        // Also avoid colliding with public zones if readable
        for extra in [
            PathBuf::from("/etc/bunker/zones.json"),
            self.path
                .parent()
                .unwrap_or(std::path::Path::new("."))
                .join("zones.json"),
        ] {
            if let Ok(raw) = fs::read_to_string(&extra) {
                if let Ok(Value::Object(m)) = serde_json::from_str(&raw) {
                    for z in m.values() {
                        if let Some(ip) = z.get("ip").and_then(|x| x.as_str()) {
                            if let Some(last) = ip.rsplit('.').next() {
                                if let Ok(n) = last.parse::<u8>() {
                                    used_ip.insert(n);
                                }
                            }
                        }
                        if let Some(s) = z.get("socks").and_then(|x| x.as_u64()) {
                            used_socks.insert(s);
                        }
                    }
                }
            }
        }
        for z in self.zones.values() {
            if let Some(ip) = z.get("ip").and_then(|x| x.as_str()) {
                if let Some(last) = ip.rsplit('.').next() {
                    if let Ok(n) = last.parse::<u8>() {
                        used_ip.insert(n);
                    }
                }
            }
            if let Some(s) = z.get("socks").and_then(|x| x.as_u64()) {
                used_socks.insert(s);
            }
            if let Some(mac) = z.get("mac").and_then(|x| x.as_str()) {
                if let Some(last) = mac.rsplit(':').next() {
                    if let Ok(n) = u8::from_str_radix(last, 16) {
                        used_mac.insert(n);
                    }
                }
            }
        }
        let ipn = (21u8..250).find(|i| !used_ip.contains(i)).unwrap_or(200);
        let socks = (1101u64..1200).find(|p| !used_socks.contains(p)).unwrap_or(1199);
        let macn = (0x21u8..0xfe).find(|i| !used_mac.contains(i)).unwrap_or(0xbb);
        (
            format!("10.0.0.{ipn}"),
            format!("02:b0:00:00:00:{macn:02x}"),
            socks,
        )
    }

    fn add_zone(&mut self, name: &str) {
        let name = name.trim();
        if name.is_empty()
            || !name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            self.status = "Name: alphanumeric / _ / -".into();
            return;
        }
        if self.zones.contains_key(name) {
            self.status = format!("exists: {name}");
            return;
        }
        let (ip, mac, socks) = self.next_free();
        self.zones.insert(
            name.into(),
            json!({
                "layer": 1,
                "panic": true,
                "template": "browser",
                "kind": "appvm",
                "ip": ip,
                "mac": mac,
                "socks": socks,
                "mem": 1536,
                "vcpu": 2,
                "disposable": false,
                "color": "purple",
                "internet": "nym",
                "usb": [],
                "apps": []
            }),
        );
        self.refresh();
        self.dirty = true;
        self.screen = Screen::Edit;
        self.status = format!("Added deniable VM {name} on layer 1 (panic=true). Save + rebuild.");
    }

    fn delete_selected(&mut self) {
        let Some(name) = self.selected().map(|s| s.to_string()) else {
            return;
        };
        self.zones.remove(&name);
        self.refresh();
        self.dirty = true;
        self.screen = Screen::List;
        self.status = format!("Removed {name}");
    }

    fn obj_mut(&mut self) -> Option<&mut Map<String, Value>> {
        let name = self.selected()?.to_string();
        self.zones.get_mut(&name)?.as_object_mut()
    }

    fn cycle_str(&mut self, key: &str, opts: &[&str]) {
        let Some(obj) = self.obj_mut() else {
            return;
        };
        let cur = obj.get(key).and_then(|x| x.as_str()).unwrap_or(opts[0]);
        let i = opts.iter().position(|m| *m == cur).unwrap_or(0);
        let next = opts[(i + 1) % opts.len()];
        obj.insert(key.into(), json!(next));
        self.dirty = true;
        self.status = format!("{key} → {next}");
    }

    fn cycle_layer(&mut self) {
        let Some(obj) = self.obj_mut() else {
            return;
        };
        let cur = obj.get("layer").and_then(|x| x.as_u64()).unwrap_or(1);
        let next = if cur >= 3 { 0 } else { cur + 1 };
        obj.insert("layer".into(), json!(next));
        self.dirty = true;
        self.status = format!("layer → {next}");
    }

    fn toggle_panic(&mut self) {
        let Some(obj) = self.obj_mut() else {
            return;
        };
        let cur = obj.get("panic").and_then(|x| x.as_bool()).unwrap_or(false);
        obj.insert("panic".into(), json!(!cur));
        self.dirty = true;
        self.status = format!("panic → {}", !cur);
    }

    fn toggle_kind(&mut self) {
        let Some(obj) = self.obj_mut() else {
            return;
        };
        let disp = obj.get("disposable").and_then(|x| x.as_bool()).unwrap_or(false)
            || obj.get("kind").and_then(|x| x.as_str()) == Some("disposable");
        let next = !disp;
        obj.insert("disposable".into(), json!(next));
        obj.insert(
            "kind".into(),
            json!(if next { "disposable" } else { "appvm" }),
        );
        self.dirty = true;
    }

    fn unlock_selected_layer(&mut self, pass: &str) {
        let layer = if let Some(name) = self.selected() {
            self.zones
                .get(name)
                .and_then(|z| z.get("layer"))
                .and_then(|x| x.as_u64())
                .unwrap_or(self.unlock_layer)
        } else {
            self.unlock_layer
        };
        let mut child = match Command::new("bunker-sflc")
            .arg("unlock")
            .arg(layer.to_string())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => {
                self.status = format!("bunker-sflc missing: {e}");
                return;
            }
        };
        if let Some(mut stdin) = child.stdin.take() {
            let _ = writeln!(stdin, "{pass}");
        }
        let out = child.wait_with_output().ok();
        let ok = out.as_ref().map(|o| o.status.success()).unwrap_or(false);
        self.status = if ok {
            format!("Unlocked layer {layer} — deniable VMs visible in GNOME")
        } else {
            let err = out
                .map(|o| String::from_utf8_lossy(&o.stderr).trim().to_string())
                .unwrap_or_default();
            format!("Unlock failed: {err}")
        };
    }

    fn lock_all(&mut self) {
        let _ = Command::new("bunker-sflc").args(["lock", "all"]).status();
        self.status = "Locked all deniable layers — VMs hidden".into();
    }
}

fn ui(f: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(5),
            Constraint::Length(3),
        ])
        .split(f.area());
    let dirty = if app.dirty { " [UNSAVED]" } else { "" };
    f.render_widget(
        Paragraph::new(format!("Deniable zone-VMs (Shufflecake){dirty}"))
            .style(Style::default().fg(Color::Magenta).add_modifier(Modifier::BOLD))
            .block(Block::default().borders(Borders::ALL)),
        chunks[0],
    );
    match app.screen {
        Screen::List => draw_list(f, chunks[1], app),
        Screen::Edit => draw_edit(f, chunks[1], app),
        Screen::Help => draw_help(f, chunks[1]),
    }
    let hint = match app.input_kind {
        InputKind::AddName => format!("new deniable zone> {}_", app.input),
        InputKind::UnlockPass => format!("layer passphrase> {}_", "*".repeat(app.input.len())),
        InputKind::ConfirmDelete => "Delete deniable zone? y/n".into(),
        InputKind::None => match app.screen {
            Screen::List => {
                "Enter edit  a add  x del  u unlock  L lock-all  w save  ?=help  q quit".into()
            }
            Screen::Edit => {
                "t template  c color  i net  k kind  l layer  p panic  w save  Esc list".into()
            }
            Screen::Help => "Esc back".into(),
        },
    };
    f.render_widget(
        Paragraph::new(Line::from(vec![
            Span::raw(hint),
            Span::raw(" | "),
            Span::styled(&app.status, Style::default().fg(Color::Yellow)),
        ]))
        .block(Block::default().borders(Borders::ALL).title("keys")),
        chunks[2],
    );
    if matches!(app.input_kind, InputKind::AddName | InputKind::UnlockPass) {
        let area = centered(chunks[1], 64, 5);
        f.render_widget(Clear, area);
        let title = if app.input_kind == InputKind::UnlockPass {
            "passphrase (not stored)"
        } else {
            "zone name"
        };
        let shown = if app.input_kind == InputKind::UnlockPass {
            "*".repeat(app.input.len())
        } else {
            app.input.clone()
        };
        f.render_widget(
            Paragraph::new(shown).block(Block::default().borders(Borders::ALL).title(title)),
            area,
        );
    }
}

fn draw_list(f: &mut Frame, area: Rect, app: &mut App) {
    let items: Vec<ListItem> = app
        .names
        .iter()
        .map(|n| {
            let z = &app.zones[n];
            let layer = z.get("layer").and_then(|x| x.as_u64()).unwrap_or(0);
            let panic = z.get("panic").and_then(|x| x.as_bool()).unwrap_or(false);
            let kind = z.get("kind").and_then(|x| x.as_str()).unwrap_or("appvm");
            ListItem::new(format!(
                "{n:<12} L{layer}  {:<5} {kind:<11} {}",
                if panic { "PANIC" } else { "-" },
                z.get("template").and_then(|x| x.as_str()).unwrap_or("-")
            ))
        })
        .collect();
    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!("deniable VMs — {}", app.path.display())),
        )
        .highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, &mut app.list);
}

fn draw_edit(f: &mut Frame, area: Rect, app: &App) {
    let Some(name) = app.selected() else {
        return;
    };
    let z = &app.zones[name];
    let lines = vec![
        Line::from(Span::styled(
            format!("  {name}"),
            Style::default()
                .fg(Color::Magenta)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(format!(
            "  [l] layer    {}",
            z.get("layer").and_then(|x| x.as_u64()).unwrap_or(0)
        )),
        Line::from(format!(
            "  [p] panic    {}  (destroyed by panic · service)",
            z.get("panic").and_then(|x| x.as_bool()).unwrap_or(false)
        )),
        Line::from(format!(
            "  [t] template {}",
            z.get("template").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(format!(
            "  [c] color    {}",
            z.get("color").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(format!(
            "  [i] internet {}",
            z.get("internet").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(format!(
            "  [k] kind     {}",
            z.get("kind").and_then(|x| x.as_str()).unwrap_or("appvm")
        )),
        Line::from(format!(
            "      ip       {}",
            z.get("ip").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(""),
        Line::from("  Whole VM disk lives on Shufflecake layer when unlocked."),
        Line::from("  Prefer this TUI — do not hand-edit Nix for deniable CRUD."),
    ];
    f.render_widget(
        Paragraph::new(lines).block(Block::default().borders(Borders::ALL)),
        area,
    );
}

fn draw_help(f: &mut Frame, area: Rect) {
    let text = vec![
        Line::from("Deniable = entire microVM zones, not files."),
        Line::from("Unlock layer → VMs appear under /run/bunker/xdg (GNOME)."),
        Line::from("Lock → hide VMs; panic flag → destroyed by panic · service."),
        Line::from("Public decoy zones stay in zones.json / zones · service."),
        Line::from("See docs/deniable.md — Shufflecake is research-grade."),
    ];
    f.render_widget(
        Paragraph::new(text).block(Block::default().borders(Borders::ALL).title("help")),
        area,
    );
}

fn centered(area: Rect, width: u16, height: u16) -> Rect {
    Rect {
        x: area.x + area.width.saturating_sub(width) / 2,
        y: area.y + area.height.saturating_sub(height) / 2,
        width: width.min(area.width),
        height: height.min(area.height),
    }
}

fn move_sel(app: &mut App, d: isize) {
    if app.names.is_empty() {
        return;
    }
    let n = app.names.len() as isize;
    let i = app.list.selected().unwrap_or(0) as isize + d;
    let i = ((i % n) + n) % n;
    app.list.select(Some(i as usize));
}

fn resolve_path() -> PathBuf {
    if let Some(p) = env::var_os("BUNKER_DENIABLE_JSON") {
        return PathBuf::from(p);
    }
    for p in [
        PathBuf::from("/etc/bunker/deniable-zones.json"),
        env::var_os("HOME")
            .map(|h| PathBuf::from(h).join("nixos-bunker/config/deniable-zones.json"))
            .unwrap_or_default(),
    ] {
        if p.is_file() {
            return p;
        }
    }
    PathBuf::from("config/deniable-zones.json")
}

fn run() -> io::Result<()> {
    let mut app = App::load(resolve_path())?;
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout))?;
    let res = loop_ui(&mut terminal, &mut app);
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    res
}

fn loop_ui(terminal: &mut Terminal<CrosstermBackend<Stdout>>, app: &mut App) -> io::Result<()> {
    loop {
        terminal.draw(|f| ui(f, app))?;
        let Event::Key(key) = event::read()? else {
            continue;
        };
        if key.kind != KeyEventKind::Press {
            continue;
        }
        if app.input_kind != InputKind::None {
            match key.code {
                KeyCode::Esc => {
                    app.input_kind = InputKind::None;
                    app.input.clear();
                }
                KeyCode::Enter => {
                    let t = app.input.clone();
                    match app.input_kind {
                        InputKind::AddName => app.add_zone(&t),
                        InputKind::UnlockPass => app.unlock_selected_layer(&t),
                        InputKind::ConfirmDelete => {}
                        InputKind::None => {}
                    }
                    app.input.clear();
                    app.input_kind = InputKind::None;
                }
                KeyCode::Char('y') | KeyCode::Char('Y')
                    if app.input_kind == InputKind::ConfirmDelete =>
                {
                    app.input_kind = InputKind::None;
                    app.delete_selected();
                }
                KeyCode::Char('n') | KeyCode::Char('N')
                    if app.input_kind == InputKind::ConfirmDelete =>
                {
                    app.input_kind = InputKind::None;
                }
                KeyCode::Backspace => {
                    app.input.pop();
                }
                KeyCode::Char(c) if app.input_kind != InputKind::ConfirmDelete => app.input.push(c),
                _ => {}
            }
            continue;
        }
        match app.screen {
            Screen::List => match key.code {
                KeyCode::Char('q') => break,
                KeyCode::Char('?') => app.screen = Screen::Help,
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save: {e}");
                    }
                }
                KeyCode::Down | KeyCode::Char('j') => move_sel(app, 1),
                KeyCode::Up | KeyCode::Char('k') => move_sel(app, -1),
                KeyCode::Enter | KeyCode::Char('e') => {
                    if app.selected().is_some() {
                        app.screen = Screen::Edit;
                    }
                }
                KeyCode::Char('a') => {
                    app.input.clear();
                    app.input_kind = InputKind::AddName;
                }
                KeyCode::Char('x') => {
                    if app.selected().is_some() {
                        app.input_kind = InputKind::ConfirmDelete;
                    }
                }
                KeyCode::Char('u') => {
                    app.input.clear();
                    app.input_kind = InputKind::UnlockPass;
                }
                KeyCode::Char('L') => app.lock_all(),
                _ => {}
            },
            Screen::Edit => match key.code {
                KeyCode::Esc => app.screen = Screen::List,
                KeyCode::Char('q') => break,
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save: {e}");
                    }
                }
                KeyCode::Char('t') => app.cycle_str("template", TEMPLATES),
                KeyCode::Char('c') => app.cycle_str("color", COLORS),
                KeyCode::Char('i') => app.cycle_str("internet", NET_MODES),
                KeyCode::Char('k') => app.toggle_kind(),
                KeyCode::Char('l') => app.cycle_layer(),
                KeyCode::Char('p') => app.toggle_panic(),
                KeyCode::Char('u') => {
                    app.input.clear();
                    app.input_kind = InputKind::UnlockPass;
                }
                KeyCode::Char('?') => app.screen = Screen::Help,
                _ => {}
            },
            Screen::Help => {
                if matches!(key.code, KeyCode::Esc | KeyCode::Char('q')) {
                    app.screen = Screen::List;
                }
            }
        }
    }
    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("bunker-deniable-tui: {e}");
        std::process::exit(1);
    }
}
