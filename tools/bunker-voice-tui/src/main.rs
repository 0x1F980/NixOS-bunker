//! Ratatui: voiceVM mic anonymizer 1→many defaults (Chimera / anonymous).
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
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
    Home,
    Voice,
    Help,
}

struct App {
    zones_path: PathBuf,
    zones: Map<String, Value>,
    screen: Screen,
    zone_names: Vec<String>,
    list: ListState,
    status: String,
    dirty: bool,
}

/// none = raw/no tunnel; anon = sox anonymous fallback; chimera = Chimera engine on voiceVM
const VOICE_MODES: &[&str] = &["none", "anon", "chimera"];

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
            screen: Screen::Home,
            zone_names,
            list,
            status: "voiceVM 10.0.0.3 anonymizes mic (Chimera/sox) → many zones.".into(),
            dirty: false,
        })
    }

    fn selected_zone(&self) -> Option<&str> {
        self.list.selected().map(|i| self.zone_names[i].as_str())
    }

    fn save(&mut self) -> io::Result<()> {
        let pretty = serde_json::to_string_pretty(&Value::Object(self.zones.clone()))
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let bak = self.zones_path.with_extension("json.bak");
        let _ = fs::copy(&self.zones_path, &bak);
        fs::write(&self.zones_path, pretty + "\n")?;
        self.dirty = false;
        self.status = format!("Saved {}", self.zones_path.display());
        Ok(())
    }

    fn cycle_voice(&mut self) {
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        let z = self.zones.get_mut(&name).unwrap();
        let obj = z.as_object_mut().unwrap();
        let cur = obj
            .get("voice")
            .and_then(|x| x.as_str())
            .unwrap_or("none");
        let idx = VOICE_MODES.iter().position(|m| *m == cur).unwrap_or(0);
        let next = VOICE_MODES[(idx + 1) % VOICE_MODES.len()];
        obj.insert("voice".into(), json!(next));
        self.dirty = true;
        self.status = format!("{name}: voice → {next}  (start voiceVM; attach on zone start)");
    }

    fn start_voice(&mut self) {
        self.status = "Starting voiceVM…".into();
        let _ = Command::new("bunker-zone-start").arg("voice").status();
        self.status = "bunker-zone-start voice".into();
    }

    fn attach_selected(&mut self) {
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        let mode = self
            .zones
            .get(&name)
            .and_then(|z| z.get("voice"))
            .and_then(|x| x.as_str())
            .unwrap_or("none");
        if mode == "none" {
            let _ = Command::new("bunker-voice-detach").arg(&name).status();
            self.status = format!("{name}: voice=none → detached");
        } else {
            let _ = Command::new("bunker-voice-attach").arg(&name).status();
            self.status = format!("{name}: attached to voiceVM anonymized mic");
        }
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
    let title = match app.screen {
        Screen::Home => "Voice broker — mic anonymizer (1→many)",
        Screen::Voice => "VOICE defaults — none | anon (sox) | chimera",
        Screen::Help => "Help",
    };
    f.render_widget(
        Paragraph::new(format!("{title}{dirty}"))
            .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
            .block(Block::default().borders(Borders::ALL)),
        chunks[0],
    );
    match app.screen {
        Screen::Home => draw_home(f, chunks[1], app),
        Screen::Voice => draw_voice(f, chunks[1], app),
        Screen::Help => draw_help(f, chunks[1]),
    }
    let hint = match app.screen {
        Screen::Home => "1 voice defaults  v start voiceVM  w save  q quit  ?=help",
        Screen::Voice => "↑↓ zone  Space/Enter cycle none→anon→chimera  a attach now  w save  Esc",
        Screen::Help => "Esc back",
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
}

fn draw_home(f: &mut Frame, area: ratatui::layout::Rect, app: &App) {
    let text = vec![
        Line::from("Infrastructure (broker — one VM, many zones):"),
        Line::from(""),
        Line::from(Span::styled(
            "  voiceVM  10.0.0.3",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from("    Mic anonymizer. Zone voice= none | anon | chimera"),
        Line::from("    Chimera = speaker-irreversible (preferred when installed)"),
        Line::from("    anon = sox pitch/band fallback (MorphMic-like anonymous)"),
        Line::from(""),
        Line::from(format!("  zones.json: {}", app.zones_path.display())),
        Line::from("  Physical mic → voiceVM only; zones pull Pulse tcp:10.0.0.3:4713"),
        Line::from(""),
        Line::from("  See docs/voice.md"),
    ];
    f.render_widget(
        Paragraph::new(text).block(Block::default().borders(Borders::ALL)),
        area,
    );
}

fn draw_voice(f: &mut Frame, area: ratatui::layout::Rect, app: &mut App) {
    let items: Vec<ListItem> = app
        .zone_names
        .iter()
        .map(|name| {
            let z = &app.zones[name];
            let voice = z.get("voice").and_then(|x| x.as_str()).unwrap_or("none");
            ListItem::new(format!("{name:<12} voice={voice}"))
        })
        .collect();
    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title("zones → voiceVM"))
        .highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, &mut app.list);
}

fn draw_help(f: &mut Frame, area: ratatui::layout::Rect) {
    let text = vec![
        Line::from("Same pattern as netVM / usbVM: one broker, many AppVMs."),
        Line::from("Engine: Chimera (Ohswedd/chimera) or sox anonymous fallback."),
        Line::from("MorphMic also has an 'anonymous' profile — similar idea."),
        Line::from("After save: rebuild optional; start voiceVM; attach per zone."),
        Line::from("Sister: defaults · service (net/usb)."),
    ];
    f.render_widget(
        Paragraph::new(text).block(Block::default().borders(Borders::ALL).title("help")),
        area,
    );
}

fn move_sel(app: &mut App, d: isize) {
    if app.zone_names.is_empty() {
        return;
    }
    let n = app.zone_names.len() as isize;
    let i = ((app.list.selected().unwrap_or(0) as isize + d) % n + n) % n;
    app.list.select(Some(i as usize));
}

fn run() -> io::Result<()> {
    let path = env::var_os("BUNKER_ZONES_JSON")
        .map(PathBuf::from)
        .or_else(|| {
            [
                env::var_os("HOME")
                    .map(|h| PathBuf::from(h).join("nixos-bunker/config/zones.json"))
                    .unwrap_or_default(),
                PathBuf::from("/etc/bunker/zones.json"),
            ]
            .into_iter()
            .find(|p| p.is_file())
        })
        .filter(|p| p.is_file())
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "zones.json not found"))?;

    let mut app = App::load(path)?;
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout))?;

    loop {
        terminal.draw(|f| ui(f, &mut app))?;
        let Event::Key(key) = event::read()? else {
            continue;
        };
        if key.kind != KeyEventKind::Press {
            continue;
        }
        match app.screen {
            Screen::Home => match key.code {
                KeyCode::Char('q') => break,
                KeyCode::Char('1') => app.screen = Screen::Voice,
                KeyCode::Char('v') => app.start_voice(),
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save: {e}");
                    }
                }
                KeyCode::Char('?') => app.screen = Screen::Help,
                _ => {}
            },
            Screen::Voice => match key.code {
                KeyCode::Esc => app.screen = Screen::Home,
                KeyCode::Char('q') => break,
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save: {e}");
                    }
                }
                KeyCode::Down | KeyCode::Char('j') => move_sel(&mut app, 1),
                KeyCode::Up | KeyCode::Char('k') => move_sel(&mut app, -1),
                KeyCode::Enter | KeyCode::Char(' ') => app.cycle_voice(),
                KeyCode::Char('a') => app.attach_selected(),
                KeyCode::Char('v') => app.start_voice(),
                _ => {}
            },
            Screen::Help => {
                if matches!(key.code, KeyCode::Esc | KeyCode::Char('q')) {
                    app.screen = Screen::Home;
                }
            }
        }
    }
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("bunker-voice-tui: {e}");
        std::process::exit(1);
    }
}
