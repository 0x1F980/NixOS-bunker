//! Minimal ratatui UI: CRUD AppVMs / Disposables in zones.json (not Nix modules).
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
    env, fs,
    io::{self, Stdout},
    path::PathBuf,
    process::Command,
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
    AddApp,
    AddUsb,
    ConfirmDelete,
}

const TEMPLATES: &[&str] = &["desktop", "dev", "browser", "radio"];
const COLORS: &[&str] = &[
    "red", "orange", "yellow", "green", "blue", "purple", "black", "gray",
];
const NET_MODES: &[&str] = &["nym", "i2p", "tor", "none"];
const MEM_STEPS: &[u64] = &[1024, 1536, 1920, 2048, 3072, 4096];

struct App {
    zones_path: PathBuf,
    zones: Map<String, Value>,
    screen: Screen,
    zone_names: Vec<String>,
    list: ListState,
    status: String,
    dirty: bool,
    input: String,
    input_kind: InputKind,
}

impl App {
    fn load(path: PathBuf) -> io::Result<Self> {
        let raw = fs::read_to_string(&path)?;
        let v: Value = serde_json::from_str(&raw)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let zones = v.as_object().cloned().ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidData, "zones.json root must be object")
        })?;
        let mut zone_names: Vec<String> = zones.keys().cloned().collect();
        zone_names.sort();
        let mut list = ListState::default();
        if !zone_names.is_empty() {
            list.select(Some(0));
        }
        Ok(Self {
            zones_path: path,
            zones,
            screen: Screen::List,
            zone_names,
            list,
            status: "Edit zones.json here — prefer this over hand-editing Nix modules.".into(),
            dirty: false,
            input: String::new(),
            input_kind: InputKind::None,
        })
    }

    fn refresh_names(&mut self) {
        let sel = self.selected_zone().map(|s| s.to_string());
        self.zone_names = self.zones.keys().cloned().collect();
        self.zone_names.sort();
        if let Some(name) = sel {
            if let Some(i) = self.zone_names.iter().position(|n| n == &name) {
                self.list.select(Some(i));
                return;
            }
        }
        if self.zone_names.is_empty() {
            self.list.select(None);
        } else {
            self.list
                .select(Some(self.list.selected().unwrap_or(0).min(self.zone_names.len() - 1)));
        }
    }

    fn selected_zone(&self) -> Option<&str> {
        self.list.selected().map(|i| self.zone_names[i].as_str())
    }

    fn save(&mut self) -> io::Result<()> {
        let v = Value::Object(self.zones.clone());
        let pretty = serde_json::to_string_pretty(&v)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let bak = self.zones_path.with_extension("json.bak");
        let _ = fs::copy(&self.zones_path, &bak);
        fs::write(&self.zones_path, pretty + "\n")?;
        self.dirty = false;
        self.status = format!(
            "Saved {}. Then: sudo nixos-rebuild switch --flake .#host",
            self.zones_path.display()
        );
        Ok(())
    }

    fn next_free(&self) -> (String, String, u64) {
        let mut used_ip = std::collections::HashSet::new();
        let mut used_socks = std::collections::HashSet::new();
        let mut used_mac = std::collections::HashSet::new();
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
        let ipn = (11u8..250).find(|i| !used_ip.contains(i)).unwrap_or(200);
        let socks = (1081u64..1200).find(|p| !used_socks.contains(p)).unwrap_or(1199);
        let macn = (0x11u8..0xfe).find(|i| !used_mac.contains(i)).unwrap_or(0xaa);
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
            self.status = "Name must be alphanumeric / _ / -".into();
            return;
        }
        if self.zones.contains_key(name) {
            self.status = format!("Zone exists: {name}");
            return;
        }
        let (ip, mac, socks) = self.next_free();
        self.zones.insert(
            name.into(),
            json!({
                "template": "browser",
                "kind": "appvm",
                "ip": ip,
                "mac": mac,
                "socks": socks,
                "mem": 1536,
                "vcpu": 2,
                "disposable": false,
                "color": "red",
                "internet": "nym",
                "usb": [],
                "apps": []
            }),
        );
        self.refresh_names();
        if let Some(i) = self.zone_names.iter().position(|n| n == name) {
            self.list.select(Some(i));
        }
        self.dirty = true;
        self.screen = Screen::Edit;
        self.status = format!("Added {name} — edit fields, then w save + nixos-rebuild");
    }

    fn delete_selected(&mut self) {
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        self.zones.remove(&name);
        self.refresh_names();
        self.dirty = true;
        self.screen = Screen::List;
        self.status = format!("Removed {name} (unsaved until w)");
    }

    fn zone_obj_mut(&mut self) -> Option<&mut Map<String, Value>> {
        let name = self.selected_zone()?.to_string();
        self.zones.get_mut(&name)?.as_object_mut()
    }

    fn cycle_str_field(&mut self, key: &str, options: &[&str]) {
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        let cur = obj.get(key).and_then(|x| x.as_str()).unwrap_or(options[0]);
        let idx = options.iter().position(|m| *m == cur).unwrap_or(0);
        let next = options[(idx + 1) % options.len()];
        obj.insert(key.into(), json!(next));
        self.dirty = true;
        self.status = format!("{key} → {next}");
    }

    fn toggle_kind(&mut self) {
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        let disp = obj
            .get("disposable")
            .and_then(|x| x.as_bool())
            .unwrap_or(false)
            || obj.get("kind").and_then(|x| x.as_str()) == Some("disposable");
        let next = !disp;
        obj.insert("disposable".into(), json!(next));
        obj.insert(
            "kind".into(),
            json!(if next { "disposable" } else { "appvm" }),
        );
        self.dirty = true;
        self.status = format!(
            "kind → {}",
            if next { "disposable" } else { "appvm" }
        );
    }

    fn cycle_mem(&mut self) {
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        let cur = obj.get("mem").and_then(|x| x.as_u64()).unwrap_or(1536);
        let idx = MEM_STEPS.iter().position(|m| *m == cur).unwrap_or(0);
        let next = MEM_STEPS[(idx + 1) % MEM_STEPS.len()];
        obj.insert("mem".into(), json!(next));
        self.dirty = true;
        self.status = format!("mem → {next}");
    }

    fn push_list(&mut self, field: &str, item: &str) {
        let item = item.trim();
        if item.is_empty() {
            return;
        }
        if field == "usb" {
            let ok = item.contains(':')
                && item.len() >= 5
                && item.chars().all(|c| c.is_ascii_hexdigit() || c == ':');
            if !ok {
                self.status = "Need vid:pid hex, e.g. 0bda:2838".into();
                return;
            }
        }
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        let arr = obj.entry(field.to_string()).or_insert_with(|| json!([]));
        let list = arr.as_array_mut().unwrap();
        let val = if field == "usb" {
            json!(item.to_lowercase())
        } else {
            json!(item)
        };
        if !list.contains(&val) {
            list.push(val);
        }
        self.dirty = true;
        self.status = format!("added {field}: {item}");
    }

    fn pop_list(&mut self, field: &str) {
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        let Some(arr) = obj.get_mut(field).and_then(|x| x.as_array_mut()) else {
            self.status = format!("{field} empty");
            return;
        };
        if arr.is_empty() {
            self.status = format!("{field} empty");
            return;
        }
        let removed = arr.pop();
        self.dirty = true;
        self.status = format!(
            "removed {field}: {}",
            removed
                .and_then(|v| v.as_str().map(|s| s.to_string()))
                .unwrap_or_default()
        );
    }

    fn start_selected(&mut self) {
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        if self.dirty {
            self.status = "Save first (w) — unsaved changes".into();
            return;
        }
        self.status = format!("Starting {name}…");
        let _ = Command::new("bunker-zone-start").arg(&name).status();
        self.status = format!("bunker-zone-start {name}");
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

    let title = match app.screen {
        Screen::List => "Bunker zones — AppVM / Disposable CRUD",
        Screen::Edit => "Edit zone (zones.json — not Nix modules)",
        Screen::Help => "Help",
    };
    let dirty = if app.dirty { "  [UNSAVED]" } else { "" };
    f.render_widget(
        Paragraph::new(format!("{title}{dirty}"))
            .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
            .block(Block::default().borders(Borders::ALL)),
        chunks[0],
    );

    match app.screen {
        Screen::List => draw_list(f, chunks[1], app),
        Screen::Edit => draw_edit(f, chunks[1], app),
        Screen::Help => draw_help(f, chunks[1]),
    }

    let hint = match app.input_kind {
        InputKind::AddName => format!("New zone name> {}_   Enter=create  Esc=cancel", app.input),
        InputKind::AddApp => format!("pkg name> {}_   Enter=add  Esc=cancel", app.input),
        InputKind::AddUsb => format!("vid:pid> {}_   Enter=add  Esc=cancel", app.input),
        InputKind::ConfirmDelete => "Delete zone?  y=yes  Esc/n=cancel".into(),
        InputKind::None => match app.screen {
            Screen::List => {
                "↑↓  Enter edit  a add  x delete  s start  w save  q quit  ?=help".into()
            }
            Screen::Edit => {
                "t template  c color  i internet  k kind  m mem  p/P apps  u/U usb  w save  Esc list"
                    .into()
            }
            Screen::Help => "Esc back".into(),
        },
    };
    f.render_widget(
        Paragraph::new(Line::from(vec![
            Span::raw(hint),
            Span::raw("  |  "),
            Span::styled(&app.status, Style::default().fg(Color::Yellow)),
        ]))
        .block(Block::default().borders(Borders::ALL).title("keys")),
        chunks[2],
    );

    if matches!(
        app.input_kind,
        InputKind::AddName | InputKind::AddApp | InputKind::AddUsb
    ) {
        let area = centered(chunks[1], 64, 5);
        f.render_widget(Clear, area);
        let title = match app.input_kind {
            InputKind::AddName => "new zone name",
            InputKind::AddApp => "nixpkgs attr (apps)",
            InputKind::AddUsb => "usb vid:pid",
            _ => "input",
        };
        f.render_widget(
            Paragraph::new(app.input.as_str())
                .block(Block::default().borders(Borders::ALL).title(title)),
            area,
        );
    }
}

fn draw_list(f: &mut Frame, area: Rect, app: &mut App) {
    let items: Vec<ListItem> = app
        .zone_names
        .iter()
        .map(|n| {
            let z = &app.zones[n];
            let kind = if z.get("kind").and_then(|x| x.as_str()) == Some("disposable")
                || z.get("disposable").and_then(|x| x.as_bool()) == Some(true)
            {
                "disposable"
            } else {
                "appvm"
            };
            let color = z.get("color").and_then(|x| x.as_str()).unwrap_or("-");
            let tmpl = z.get("template").and_then(|x| x.as_str()).unwrap_or("-");
            let net = z.get("internet").and_then(|x| x.as_str()).unwrap_or("-");
            let ip = z.get("ip").and_then(|x| x.as_str()).unwrap_or("-");
            ListItem::new(format!(
                "{n:<12} {kind:<11} {color:<8} {tmpl:<8} {net:<6} {ip}"
            ))
        })
        .collect();
    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(format!(
            "NAME         TYPE        COLOR    TMPL     NET    IP   ({})",
            app.zones_path.display()
        )))
        .highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, &mut app.list);
}

fn draw_edit(f: &mut Frame, area: Rect, app: &App) {
    let Some(name) = app.selected_zone() else {
        f.render_widget(
            Paragraph::new("No zone selected").block(Block::default().borders(Borders::ALL)),
            area,
        );
        return;
    };
    let z = &app.zones[name];
    let kind = z
        .get("kind")
        .and_then(|x| x.as_str())
        .unwrap_or("appvm");
    let apps = z
        .get("apps")
        .and_then(|x| x.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|v| v.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        })
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "-".into());
    let usb = z
        .get("usb")
        .and_then(|x| x.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|v| v.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        })
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "-".into());
    let lines = vec![
        Line::from(Span::styled(
            format!("  {name}"),
            Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(format!(
            "  [t] template   {}",
            z.get("template").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(format!(
            "  [c] color      {}",
            z.get("color").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(format!(
            "  [i] internet   {}",
            z.get("internet").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(format!("  [k] kind       {kind}")),
        Line::from(format!(
            "  [m] mem        {}",
            z.get("mem").and_then(|x| x.as_u64()).unwrap_or(0)
        )),
        Line::from(format!(
            "      ip/mac     {}  /  {}",
            z.get("ip").and_then(|x| x.as_str()).unwrap_or("-"),
            z.get("mac").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(format!(
            "      socks      {}",
            z.get("socks").and_then(|x| x.as_u64()).unwrap_or(0)
        )),
        Line::from(format!("  [p] apps add   {apps}")),
        Line::from("  [P] apps pop last"),
        Line::from(format!("  [u] usb add    {usb}")),
        Line::from("  [U] usb pop last"),
        Line::from(""),
        Line::from("  Prefer this TUI / bunker-zone CLI. Do not edit modules/ for per-zone CRUD."),
        Line::from("  After save: sudo nixos-rebuild switch --flake .#host"),
    ];
    f.render_widget(
        Paragraph::new(lines).block(Block::default().borders(Borders::ALL).title("fields")),
        area,
    );
}

fn draw_help(f: &mut Frame, area: Rect) {
    let text = vec![
        Line::from("Recommended UX:"),
        Line::from("  • zones · service (this app)  OR  bunker-zone CLI  →  zones.json"),
        Line::from("  • defaults · service          →  net/usb broker defaults"),
        Line::from("  • Hand-edit zones.json        →  OK (same source of truth)"),
        Line::from("  • Hand-edit Nix modules       →  discouraged for zone CRUD"),
        Line::from(""),
        Line::from("List:  a add  Enter edit  x delete  s start  w save"),
        Line::from("Edit:  t/c/i/k/m cycle  p/P apps  u/U usb"),
        Line::from("Rebuild after save so launchers / guests pick up changes."),
    ];
    f.render_widget(
        Paragraph::new(text).block(Block::default().borders(Borders::ALL).title("help")),
        area,
    );
}

fn centered(area: Rect, width: u16, height: u16) -> Rect {
    let x = area.x + area.width.saturating_sub(width) / 2;
    let y = area.y + area.height.saturating_sub(height) / 2;
    Rect {
        x,
        y,
        width: width.min(area.width),
        height: height.min(area.height),
    }
}

fn move_sel(app: &mut App, delta: isize) {
    if app.zone_names.is_empty() {
        return;
    }
    let n = app.zone_names.len();
    let i = app.list.selected().unwrap_or(0) as isize + delta;
    let i = if i < 0 {
        n - 1
    } else if i as usize >= n {
        0
    } else {
        i as usize
    };
    app.list.select(Some(i));
}

fn run() -> io::Result<()> {
    let path = env::var_os("BUNKER_ZONES_JSON")
        .map(PathBuf::from)
        .or_else(|| {
            [
                dirs_home().join("nixos-bunker/config/zones.json"),
                PathBuf::from("/etc/bunker/zones.json"),
            ]
            .into_iter()
            .find(|p| p.is_file())
        })
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::NotFound,
                "set BUNKER_ZONES_JSON or place config/zones.json",
            )
        })?;

    let mut app = App::load(path)?;
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let res = event_loop(&mut terminal, &mut app);

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    res
}

fn dirs_home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn event_loop(terminal: &mut Terminal<CrosstermBackend<Stdout>>, app: &mut App) -> io::Result<()> {
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
                KeyCode::Char('n') | KeyCode::Char('N')
                    if app.input_kind == InputKind::ConfirmDelete =>
                {
                    app.input_kind = InputKind::None;
                }
                KeyCode::Char('y') | KeyCode::Char('Y')
                    if app.input_kind == InputKind::ConfirmDelete =>
                {
                    app.input_kind = InputKind::None;
                    app.delete_selected();
                }
                KeyCode::Enter => {
                    let text = app.input.clone();
                    match app.input_kind {
                        InputKind::AddName => app.add_zone(&text),
                        InputKind::AddApp => app.push_list("apps", &text),
                        InputKind::AddUsb => app.push_list("usb", &text),
                        InputKind::ConfirmDelete | InputKind::None => {}
                    }
                    app.input.clear();
                    app.input_kind = InputKind::None;
                }
                KeyCode::Backspace => {
                    app.input.pop();
                }
                KeyCode::Char(c) if app.input_kind != InputKind::ConfirmDelete => {
                    app.input.push(c);
                }
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
                        app.status = format!("save failed: {e}");
                    }
                }
                KeyCode::Down | KeyCode::Char('j') => move_sel(app, 1),
                KeyCode::Up | KeyCode::Char('k') => move_sel(app, -1),
                KeyCode::Enter | KeyCode::Char('e') => {
                    if app.selected_zone().is_some() {
                        app.screen = Screen::Edit;
                    }
                }
                KeyCode::Char('a') => {
                    app.input.clear();
                    app.input_kind = InputKind::AddName;
                }
                KeyCode::Char('x') | KeyCode::Char('d') => {
                    if app.selected_zone().is_some() {
                        app.input_kind = InputKind::ConfirmDelete;
                    }
                }
                KeyCode::Char('s') => app.start_selected(),
                _ => {}
            },
            Screen::Edit => match key.code {
                KeyCode::Esc => app.screen = Screen::List,
                KeyCode::Char('q') => break,
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save failed: {e}");
                    }
                }
                KeyCode::Char('t') => app.cycle_str_field("template", TEMPLATES),
                KeyCode::Char('c') => app.cycle_str_field("color", COLORS),
                KeyCode::Char('i') => app.cycle_str_field("internet", NET_MODES),
                KeyCode::Char('k') => app.toggle_kind(),
                KeyCode::Char('m') => app.cycle_mem(),
                KeyCode::Char('p') => {
                    app.input.clear();
                    app.input_kind = InputKind::AddApp;
                }
                KeyCode::Char('P') => app.pop_list("apps"),
                KeyCode::Char('u') => {
                    app.input.clear();
                    app.input_kind = InputKind::AddUsb;
                }
                KeyCode::Char('U') => app.pop_list("usb"),
                KeyCode::Char('s') => app.start_selected(),
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
        eprintln!("bunker-zones-tui: {e}");
        std::process::exit(1);
    }
}
