# Git controls in the detail screen: design

Date: 2026-11-03

## Why

The user pulls each service's latest code about twice a day and sometimes switches branches. Today that means opening VS Code or a terminal. The goal is to do it from Şalter's detail screen, typically right before pressing "Başlat".

## Goals

1. The detail screen shows the branch the service's repo is on.
2. The user can switch branches from there. The list includes local branches and remote branches; picking a remote-only branch creates a local tracking branch and switches to it.
3. The user can `git pull` from there.
4. Uncommitted local changes are handled politely.
   - **Branch switch:** blocked, with a gentle warning that says why (e.g. "3 dosyada kaydedilmemiş değişiklik var; önce commit'le ya da geri al").
   - **Pull:** allowed whenever git allows it. If git refuses (local changes would be overwritten, or a fast-forward is impossible), show the reason gently, in Turkish.
5. If any service of that repo is running when a pull or switch changes the code, ask "yeniden başlatayım mı?". Never restart automatically. (Claude's call; the user said "evet" to the asked-or-auto question without choosing.)

## Non-goals / anti-goals

- No commit, push, stash, merge, rebase, conflict resolution, diff view, branch creation from scratch, or branch deletion. Those stay in VS Code or the terminal.
- No git UI in the menu-bar popover or the sidebar. The detail screen is enough for now.
- Anti-goal: leaving a repo in a half-merged or conflicted state because of a Şalter action.
- Anti-goal: hanging forever on a password or passphrase prompt.
- Anti-goal: silently discarding or overwriting local changes.

## Constraints

- Git is a **repo-level** concept. Every service in the same repo shares the branch. Example: storefront has BFF and Order Worker, and switching from either detail screen switches both. The UI should make that visible.
- Commands run with the user's captured shell environment (`ShellEnvironment`, the same `PATH` and `SSH_AUTH_SOCK` the services get), in the repo's directory.
- They must never prompt: `GIT_TERMINAL_PROMPT=0`, `GIT_ASKPASS` unset/empty, and `ssh -o BatchMode=yes` via `GIT_SSH_COMMAND` unless the user already set one.
- Network commands (fetch/pull) get a timeout (~60 s). On timeout the process is killed and the user sees a message.
- The user's real repos have one remote, `origin`, and track upstreams such as `origin/develop`, `origin/main` and `origin/dev`.
- Existing app patterns:
  - SalterCore holds pure, tested logic; the Salter target holds views.
  - The Linear-style design language from `2026-11-02-ui-redesign-design.md` applies: tokens, quiet buttons, a single primary action.
  - All UI copy is Turkish.
- Command output must not appear as noise in the service logs. One short system line per action in each affected service's log is fine: "git pull: 3 yeni commit", "branch: feature/x".

## Behaviour

### What the detail screen shows
A git row in the detail header, near the command line:
- The **branch button** shows a branch icon and the current branch name, e.g. `develop`, and opens the branch picker.
  - In detached HEAD it shows the short commit (`a1b2c3d`) with the label "ayrık HEAD". The picker still works.
- A **sync status** in tertiary text:
  - "↓3" (behind upstream), "↑1" (ahead), "güncel" (up to date), or "upstream yok" (no upstream).
  - These come from the last fetch; "son kontrol 5 dk önce" appears in the tooltip.
- **"Çek" (pull) button**, a quiet button. It is disabled when there is no upstream, in detached HEAD, or while an operation runs.
- **Dirty indicator:** when tracked files are modified, a small "● 3 değişiklik" in warn color. The tooltip lists up to ~10 file paths.
- If the repo is not a git repo, the row is hidden.

### Freshness
- When the detail screen of a repo opens, Şalter runs `git fetch` in the background, at most once per 5 min per repo. This keeps ↓/↑ meaningful. (Claude's call.)
- Local state (branch, dirty files, ahead/behind against the cached upstream) is re-read without the network:
  - when the detail screen opens,
  - when the window becomes active,
  - after every Şalter git action.
- Changes made in VS Code or a terminal therefore show up when the user returns.

### Branch picker
- It opens as a popover from the branch button. It has a search field on top, then two sections:
  - **Yerel**: local branches, current one checked.
  - **Uzak**: remote branches that have no local branch of the same name, listed without the `origin/` prefix and excluding `HEAD`.
- Opening it triggers a fetch (if the last one is older than ~30 s) so a colleague's new branch appears. A small spinner shows while fetching. The list is usable immediately from cached refs and refreshes when fetch ends.
- Picking a branch:
  1. If tracked files are modified, block. The picker shows the gentle warning inline. Untracked files do not block, since git itself allows the switch.
  2. If the branch is local, run `git switch <name>`.
  3. If it is remote-only, run `git switch -c <name> --track origin/<name>`.
  4. If git still refuses (e.g. an untracked file would be overwritten), show git's reason, translated or summarised in Turkish, plus the raw message in a disclosure.
- After a successful switch, show the restart prompt if any service of the repo is running (see below).

### Pull
- Runs `git pull --ff-only`. (Claude's call: it never creates merge commits or conflicts, so the repo cannot be left half-merged.)
- Outcomes and messages:

  | Outcome | Message |
  |---|---|
  | Success with new commits | "3 yeni commit çekildi" |
  | Already up to date | "Zaten güncel" |
  | Local changes would be overwritten | "Yerel değişiklikler çekilecek dosyalarla çakışıyor: <files>" |
  | Diverged (local commits not on remote) | "Yerel ve uzak branch ayrışmış; birleştirmeyi VS Code ya da terminalden yap." |
  | Auth or network failure | "Uzak sunucuya bağlanılamadı" plus the raw message in a disclosure |
  | Timeout | "Uzak sunucuya bağlanılamadı (zaman aşımı)" |

- The result appears as a small transient message next to the git row (auto-hides after ~5 s for success; errors stay until dismissed).
- Success also writes one system line to each service log of that repo.

### Restart prompt
- Shown when a pull brought new commits or a switch succeeded, and at least one service of that repo is active.
- It is an alert: "<repo> güncellendi. Çalışan N servis yeniden başlatılsın mı?" with the buttons "Yeniden başlat" (default) and "Sonra".
- "Yeniden başlat" restarts exactly those running services with the existing restart path.

### Concurrency
- One git operation per repo at a time. While one runs:
  - the branch button and the Çek button are disabled;
  - a spinner is shown;
  - the other services' detail screens of the same repo show the same busy state.
- Operations in different repos may run in parallel.

## Left to the builder
- The exact layout of the git row and picker, within the design language.
- Parsing approach: porcelain formats are preferred, e.g. `git status --porcelain=v2 --branch` and `git for-each-ref --format`.
- Exact mapping of git error output to Turkish messages beyond the cases listed.
- Where the git runner lives (a SalterCore type that runs a `SpawnRequest`-like command and returns exit code + output is the natural fit).
- How the 5 min / 30 s fetch throttles are stored.

## Tests
SalterCore unit tests:
- Parsing of `git status --porcelain=v2 --branch` (branch, detached, upstream, ahead/behind, tracked vs untracked changes).
- Parsing of the branch list (local vs remote-only, HEAD excluded).
- The command each action builds (switch local / switch remote / pull), including the no-prompt environment.
- Error-message classification from git stderr samples.

Integration tests against real temporary git repos (`git init` plus a bare "remote" in a temp dir, no network):
- Switching blocked by dirty files.
- Remote-only branch creates tracking.
- `pull --ff-only` fast-forward, already up to date, diverged, and local-changes-would-be-overwritten.

## Claude's calls (the user approved the direction, not these individually)
- Restart prompt after a change, never automatic.
- `pull --ff-only`, not the user's configured pull mode.
- Background fetch on detail open (≤ every 5 min per repo) and on picker open (≤ every 30 s).
- Untracked files do not block a branch switch; only tracked modifications do.
- One system line per git action in the service logs.
- Git UI only in the detail screen.
