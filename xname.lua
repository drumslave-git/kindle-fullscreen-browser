-- xname.lua: list X windows and edit their titles, via LuaJIT FFI and libX11.
-- Runs with KOReader's LuaJIT on the Kindle:  /mnt/us/koreader/luajit xname.lua <command> ...
--
--   list                          every window with a title or a big size: id, geometry, map state, titles
--   set   MATCH FROM TO           in each window whose title contains MATCH and FROM, replace FROM with TO
--                                 (exit 0 if a window was changed or already had TO, 1 if none was found)
--   keep  MATCH FROM TO SECONDS [INTERVAL [PID]]
--                                 like set, re-checked every INTERVAL seconds (default 1)
--                                 for SECONDS (0 = until killed); prints a line per change.
--                                 With PID: when that process is gone, change TO back to FROM and exit.
--
-- The Kindle window manager reads layout tags from a window's title; for example
-- "_PC:TS_" asks for the top bars and "_PC:N_" for none.

local ffi = require("ffi")
-- The X error handler below is a Lua callback; callbacks must not fire from JIT-compiled code.
jit.off()
ffi.cdef[[
typedef struct _XDisplay Display;
typedef unsigned long XID;
typedef XID Window;
typedef unsigned long Atom;
typedef struct {
    int x, y, width, height, border_width, depth;
    void *visual;
    Window root;
    int c_class, bit_gravity, win_gravity, backing_store;
    unsigned long backing_planes, backing_pixel;
    int save_under;
    unsigned long colormap;
    int map_installed, map_state;
    long all_event_masks, your_event_mask, do_not_propagate_mask;
    int override_redirect;
    void *screen;
} XWindowAttributes;
typedef int (*XErrorHandler)(Display *, void *);
Display *XOpenDisplay(const char *);
int XCloseDisplay(Display *);
Window XDefaultRootWindow(Display *);
int XQueryTree(Display *, Window, Window *, Window *, Window **, unsigned int *);
int XFree(void *);
Atom XInternAtom(Display *, const char *, int);
int XGetWindowProperty(Display *, Window, Atom, long, long, int, Atom, Atom *, int *,
                       unsigned long *, unsigned long *, unsigned char **);
int XChangeProperty(Display *, Window, Atom, Atom, int, int, const char *, int);
int XGetWindowAttributes(Display *, Window, XWindowAttributes *);
int XSync(Display *, int);
XErrorHandler XSetErrorHandler(XErrorHandler);
int usleep(unsigned int);
int kill(int, int);
]]

local X = ffi.load("libX11.so.6")
-- Windows can vanish between listing and reading them; ignore those errors instead of exiting.
local onError = ffi.cast("XErrorHandler", function() return 0 end)
X.XSetErrorHandler(onError)

local dpy = X.XOpenDisplay(os.getenv("DISPLAY") or ":0")
if dpy == nil then
    io.stderr:write("xname: cannot open display\n")
    os.exit(2)
end
local XA_STRING, XA_WM_NAME = 31, 39
local NET_WM_NAME = X.XInternAtom(dpy, "_NET_WM_NAME", 0)
local UTF8_STRING = X.XInternAtom(dpy, "UTF8_STRING", 0)

local function getText(w, atom)
    local typ, fmt = ffi.new("Atom[1]"), ffi.new("int[1]")
    local n, after = ffi.new("unsigned long[1]"), ffi.new("unsigned long[1]")
    local data = ffi.new("unsigned char *[1]")
    if X.XGetWindowProperty(dpy, w, atom, 0, 4096, 0, 0, typ, fmt, n, after, data) ~= 0 then
        return nil
    end
    if data[0] == nil then return nil end
    local s
    if fmt[0] == 8 and n[0] > 0 then s = ffi.string(data[0], n[0]) end
    X.XFree(data[0])
    return s, tonumber(typ[0])
end

local function titles(w)
    return getText(w, XA_WM_NAME), getText(w, NET_WM_NAME)
end

local function forEachWindow(fn)
    local function walk(w, depth)
        fn(w, depth)
        local root, parent = ffi.new("Window[1]"), ffi.new("Window[1]")
        local kids, nk = ffi.new("Window *[1]"), ffi.new("unsigned int[1]")
        if X.XQueryTree(dpy, w, root, parent, kids, nk) == 0 then return end
        local list = {}
        for i = 0, tonumber(nk[0]) - 1 do list[#list + 1] = kids[0][i] end
        if kids[0] ~= nil then X.XFree(kids[0]) end
        for _, k in ipairs(list) do walk(k, depth + 1) end
    end
    walk(X.XDefaultRootWindow(dpy), 0)
end

local function replacePlain(s, from, to)
    local i, j = s:find(from, 1, true)
    if not i then return s end
    return s:sub(1, i - 1) .. to .. s:sub(j + 1)
end

-- One pass of "set". Returns changed, found (found also counts windows that already had TO).
local function setOnce(match, from, to)
    local changed, found = 0, 0
    forEachWindow(function(w)
        local wm, net = titles(w)
        local cur = net or wm
        if not cur or not cur:find(match, 1, true) then return end
        if cur:find(from, 1, true) then
            local new = replacePlain(cur, from, to)
            local _, wmType = getText(w, XA_WM_NAME)
            X.XChangeProperty(dpy, w, XA_WM_NAME, wmType or XA_STRING, 8, 0, new, #new)
            X.XChangeProperty(dpy, w, NET_WM_NAME, UTF8_STRING, 8, 0, new, #new)
            changed, found = changed + 1, found + 1
            print(string.format("%s set 0x%x: %s", os.date("%H:%M:%S"), tonumber(w), new))
        elseif cur:find(to, 1, true) then
            found = found + 1
        end
    end)
    X.XSync(dpy, 0)
    return changed, found
end

local cmd = arg[1]
if cmd == "list" then
    local attr = ffi.new("XWindowAttributes")
    forEachWindow(function(w, depth)
        local wm, net = titles(w)
        local ok = X.XGetWindowAttributes(dpy, w, attr) ~= 0
        local big = ok and attr.width * attr.height >= 200000
        if wm or net or big then
            print(string.format("%s0x%x %dx%d+%d+%d map=%d%s wm=%q net=%q",
                string.rep("  ", depth), tonumber(w),
                ok and attr.width or -1, ok and attr.height or -1, ok and attr.x or -1, ok and attr.y or -1,
                ok and attr.map_state or -1, (ok and attr.override_redirect ~= 0) and " override" or "",
                wm or "", net or ""))
        end
    end)
elseif cmd == "set" and arg[4] then
    local _, found = setOnce(arg[2], arg[3], arg[4])
    X.XCloseDisplay(dpy)
    os.exit(found > 0 and 0 or 1)
elseif cmd == "keep" and arg[4] then
    local secs = tonumber(arg[5] or "0") or 0
    local interval = tonumber(arg[6] or "1") or 1
    local owner = tonumber(arg[7] or "")
    local t = 0
    while secs == 0 or t < secs do
        if owner and ffi.C.kill(owner, 0) ~= 0 then
            -- The script that started us is gone: undo the change, so the window is normal again.
            setOnce(arg[2], arg[4], arg[3])
            print(string.format("%s owner %d gone, title restored", os.date("%H:%M:%S"), owner))
            break
        end
        setOnce(arg[2], arg[3], arg[4])
        io.stdout:flush()
        ffi.C.usleep(math.floor(interval * 1000000))
        t = t + interval
    end
else
    io.stderr:write("usage: xname.lua list | set MATCH FROM TO | keep MATCH FROM TO SECONDS [INTERVAL [PID]]\n")
    os.exit(2)
end
X.XCloseDisplay(dpy)
