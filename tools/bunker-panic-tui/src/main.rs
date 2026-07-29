//! Panic button — confirm + code → wipe panic-flagged deniable VM keys + best-effort RAM wipe.
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
    widgets::{Block, Borders, Paragraph},
    Frame, Terminal,
};
use std::{
    io::{self, Write as IoWrite, Stdout},
    process::{Command, Stdio},
};

enum Phase {
    Warn,
    Code,
    Done(String),
}

struct App {
    phase: Phase,
    code: String,
    status: String,
}

fn ui(f: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(5),
            Constraint::Min(8),
            Constraint::Length(3),
        ])
        .split(f.area());

    f.render_widget(
        Paragraph::new(vec![
            Line::from(Span::styled(
                "  ☢  BUNKER PANIC  ☢",
                Style::default()
                    .fg(Color::Red)
                    .add_modifier(Modifier::BOLD),
            )),
            Line::from("  Destroys panic-flagged deniable zone-VM keys/state"),
            Line::from("  Does NOT wipe public decoy zones or host LUKS"),
        ])
        .block(Block::default().borders(Borders::ALL).title("WARNING")),
        chunks[0],
    );

    let body = match &app.phase {
        Phase::Warn => vec![
            Line::from(""),
            Line::from("  This will:"),
            Line::from("    • stop panic-flagged deniable microVMs"),
            Line::from("    • shred their unlocked disks / layer crumbs"),
            Line::from("    • lock all deniable layers (hide VMs)"),
            Line::from("    • best-effort RAM wipe (sdmem) — reboot after"),
            Line::from(""),
            Line::from("  Press Enter to type panic code, or q to abort."),
        ],
        Phase::Code => vec![
            Line::from(""),
            Line::from(format!(
                "  Panic code> {}",
                "*".repeat(app.code.len())
            )),
            Line::from(""),
            Line::from("  Enter = run    Esc = abort"),
        ],
        Phase::Done(msg) => vec![
            Line::from(""),
            Line::from(Span::styled(
                format!("  {msg}"),
                Style::default().fg(Color::Yellow),
            )),
            Line::from(""),
            Line::from("  Recommended:  sudo systemctl reboot"),
            Line::from("  Press q to quit."),
        ],
    };
    f.render_widget(
        Paragraph::new(body).block(Block::default().borders(Borders::ALL).title("action")),
        chunks[1],
    );
    f.render_widget(
        Paragraph::new(Span::styled(
            &app.status,
            Style::default().fg(Color::Yellow),
        ))
        .block(Block::default().borders(Borders::ALL)),
        chunks[2],
    );
}

fn run_panic(code: &str) -> String {
    let mut child = match Command::new("sudo")
        .args(["-n", "bunker-panic", "--yes"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(_) => {
            // fallback without sudo -n
            match Command::new("bunker-panic")
                .arg("--yes")
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
            {
                Ok(c) => c,
                Err(e) => return format!("cannot spawn bunker-panic: {e}"),
            }
        }
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = writeln!(stdin, "{code}");
    }
    match child.wait_with_output() {
        Ok(o) if o.status.success() => {
            let out = String::from_utf8_lossy(&o.stdout);
            out.lines()
                .last()
                .unwrap_or("panic OK — reboot recommended")
                .to_string()
        }
        Ok(o) => {
            let err = String::from_utf8_lossy(&o.stderr);
            if err.contains("denied") || String::from_utf8_lossy(&o.stdout).contains("denied") {
                "denied".into()
            } else {
                format!(
                    "failed: {}",
                    err.trim().lines().last().unwrap_or("unknown")
                )
            }
        }
        Err(e) => format!("wait: {e}"),
    }
}

fn run() -> io::Result<()> {
    let mut app = App {
        phase: Phase::Warn,
        code: String::new(),
        status: "Nuclear option for deniable VMs only".into(),
    };
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout))?;

    loop {
        terminal.draw(|f| ui(f, &app))?;
        let Event::Key(key) = event::read()? else {
            continue;
        };
        if key.kind != KeyEventKind::Press {
            continue;
        }
        match &app.phase {
            Phase::Warn => match key.code {
                KeyCode::Char('q') | KeyCode::Esc => break,
                KeyCode::Enter => {
                    app.phase = Phase::Code;
                    app.status = "Enter panic passphrase".into();
                }
                _ => {}
            },
            Phase::Code => match key.code {
                KeyCode::Esc => {
                    app.phase = Phase::Warn;
                    app.code.clear();
                    app.status = "Aborted".into();
                }
                KeyCode::Char('q') => break,
                KeyCode::Backspace => {
                    app.code.pop();
                }
                KeyCode::Enter => {
                    app.status = "Running panic…".into();
                    terminal.draw(|f| ui(f, &app))?;
                    let msg = run_panic(&app.code);
                    app.code.clear();
                    app.phase = Phase::Done(msg);
                    app.status = "Done".into();
                }
                KeyCode::Char(c) => app.code.push(c),
                _ => {}
            },
            Phase::Done(_) => {
                if matches!(key.code, KeyCode::Char('q') | KeyCode::Esc | KeyCode::Enter) {
                    break;
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
        eprintln!("bunker-panic-tui: {e}");
        std::process::exit(1);
    }
}
