```
███████╗██╗    ██╗███╗   ███╗
╚══███╔╝██║    ██║████╗ ████║
  ███╔╝ ██║ █╗ ██║██╔████╔██║
 ███╔╝  ██║███╗██║██║╚██╔╝██║
███████╗╚███╔███╔╝██║ ╚═╝ ██║
╚══════╝ ╚══╝╚══╝ ╚═╝     ╚═╝
```

Zwm is a dwm-inspired minimal tiling window manager for X implemented in Zig programming language.

My main goals for creating Zwm are learning Zig and implementing a minimal window manager for personal use
that is easier to hack than dwm. Both goals are work in progress :)

### Current state

- [x] Basic tiling layout
- [x] Workspaces (tags)
- [x] Focus and window management commands
- [x] Spawn process command
- [x] Customizable config file
- [x] Hot reloading with persisted windows state (requires a script)
- [ ] Status bar
- [ ] Multi-monitor support
- [ ] Floating windows
- [ ] Support for adding new layouts
- [ ] More built-in layouts: fullscreen, 3-column, ...
- [ ] Icon tray
- [ ] ICCCM and EWMH support
- [ ] Iron out issues with focus, window management, and general UX

# Installation

You will need at least git and zig installed.

```bash
git clone https://github.com/zuranthus/zwm.git
cd zwm
sudo zig build install -p /usr/local
```
### Configuration

Modify `src/config.zig` before building and installing.

# Usage

The easiest way is to start zwm with `startx` by adding `exec zwm` to `~/.xinitrc`.

### Hot Reloading

It is possible to restart zwm while keeping windows and their workspace distribution intact. This makes updating zwm binary a quick and painless process.

Enabling hot reloading is easy: use the following script in `~/.xinitrc` instead of a simple `exec zwm`
```bash
while :
do
  zwm --save-state ~/.zwm.state
  [[ $? == 42 ]] || break;
done
```

Now if you build and install a new zwm build, restart zwm with `Mod + Shift + Q` (configurable in `src/config.zig`). Voilà: you are running the new build and all windows are alive and in their workspaces.
