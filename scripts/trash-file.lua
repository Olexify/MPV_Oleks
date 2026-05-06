-- trash-file.lua  ── place in your mpv/scripts/ folder ─────────────────────
--
-- DEL           → arm "move to Trash / Recycle Bin"   (press again to confirm)
-- Shift+DEL     → arm "permanently delete"             (press again to confirm)
-- Ctrl+Z        → undo last trash operation (up to 5 levels)

local mp    = require('mp')
local utils = require('mp.utils')

-- ── platform ──────────────────────────────────────────────────────────────────
local platform = (function()
    local p = mp.get_property_native('platform')
    if p then return p end
    if os.getenv('windir') ~= nil then return 'windows' end
    local home = os.getenv('HOME')
    if home and home:sub(1, 6) == '/Users' then return 'darwin' end
    return 'linux'
end)()

-- ── helpers ───────────────────────────────────────────────────────────────────
local function get_local_path()
    local path = mp.get_property('path')
    if not path then return nil end
    if path:match('^%a[%a%d+%-%.]*://') then return nil end
    local cwd = mp.get_property('working-directory', '')
    if platform == 'windows' then
        if not path:match('^%a:[/\\]') and not path:match('^\\\\') then
            path = utils.join_path(cwd, path)
        end
    else
        if not path:match('^/') then
            path = utils.join_path(cwd, path)
        end
    end
    return path
end

local function navigate_away()
    local count = mp.get_property_native('playlist-count', 0)
    if count > 1 then
        local pos = mp.get_property_native('playlist-pos', 0)
        if pos < count - 1 then
            mp.command('playlist-next force')
        else
            mp.command('playlist-prev force')
        end
    else
        mp.command('stop')
    end
end

local function ass_safe(s)
    return tostring(s):gsub('{', '\\{'):gsub('}', '\\}')
end

-- Escape for PowerShell single-quoted string (only ' → '')
local function ps_sq(s)
    return s:gsub("'", "''")
end

-- ── styled OSD overlay ────────────────────────────────────────────────────────
local function make_overlay(action_type, name, secs)
    local ov = mp.create_osd_overlay('ass-events')
    ov.res_x = 1280
    ov.res_y = 720

    local cx  = 640
    local top = 52

    local safe    = ass_safe(name)
    local display = #safe > 52 and ('...' .. safe:sub(-49)) or safe

    local title_color, title_text, hint_key
    if action_type == 'trash' then
        title_color = '\\c&H0099FF&'
        title_text  = 'MOVE TO TRASH'
        hint_key    = 'DEL'
    else
        title_color = '\\c&H0022FF&'
        title_text  = 'DELETE PERMANENTLY'
        hint_key    = 'Shift+DEL'
    end

    local bord = '\\bord3\\shad3\\3c&H000000&\\4c&H101010&'

    local ass = table.concat({
        string.format('{\\an8\\pos(%d,%d)\\fs56\\b1%s%s}%s',
            cx, top, title_color, bord, title_text),
        string.format('{\\an8\\pos(%d,%d)\\fs38\\c&HFFFFFF&%s}%s',
            cx, top + 84, bord, display),
        string.format('{\\an8\\pos(%d,%d)\\fs8\\c&H666666&\\bord0\\shad0}%s',
            cx, top + 136, string.rep('─', 44)),
        string.format('{\\an8\\pos(%d,%d)\\fs28\\i1\\c&HCCBBAA&\\bord2\\shad0}Press %s again to confirm   •   auto-cancels in %ds',
            cx, top + 162, hint_key, secs),
    }, '\n')

    ov.data = ass
    ov:update()
    return ov
end

local function simple_osd(msg, secs)
    mp.osd_message(msg, secs or 3)
end

-- ── undo stack ────────────────────────────────────────────────────────────────
local undo_stack = {}

local function push_undo(path)
    table.insert(undo_stack, path)
    if #undo_stack > 5 then table.remove(undo_stack, 1) end
end

-- ── restore from trash ────────────────────────────────────────────────────────
local function restore_from_trash(path)
    local ok = false

    if platform == 'windows' then
        local safe_path = ps_sq(path)
        local ps = string.format([[
$target = '%s'
$target = $target.Replace('/', '\')
$shell  = New-Object -ComObject Shell.Application
$bin    = $shell.Namespace(10)
$found  = $false
foreach ($item in $bin.Items()) {
    $dir  = ($bin.GetDetailsOf($item, 1)).Trim().TrimEnd('\')
    $full = [System.IO.Path]::Combine($dir, $item.Name)
    if ([string]::Equals($full, $target, [System.StringComparison]::OrdinalIgnoreCase)) {
        $binPath  = $item.Path
        $binDir   = [System.IO.Path]::GetDirectoryName($binPath)
        $binName  = [System.IO.Path]::GetFileName($binPath)
        $infoPath = [System.IO.Path]::Combine($binDir, '$I' + $binName.Substring(2))

        $destDir = [System.IO.Path]::GetDirectoryName($target)
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        Move-Item -LiteralPath $binPath -Destination $target -Force
        if (Test-Path -LiteralPath $infoPath) {
            Remove-Item -LiteralPath $infoPath -Force
        }
        $found = $true
        break
    }
}
if (-not $found) { exit 1 }
]], safe_path)
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'powershell', '-NoProfile', '-NonInteractive', '-Command', ps},
        })
        ok = res.status == 0

    elseif platform == 'darwin' then
        local escaped = path:gsub('"', '\\"')
        local script = string.format([[
tell application "Finder"
    repeat with ti in (every item of trash)
        try
            if POSIX path of (ti as alias) contains "%s" then
                put back ti
                exit repeat
            end if
        end try
    end repeat
end tell]], escaped)
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'osascript', '-e', script},
        })
        ok = res.status == 0

    else  -- Linux
        local uri = 'trash:///' .. (path:match('[^/]+$') or path)
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'gio', 'trash', '--restore', uri},
        })
        ok = res.status == 0
    end

    return ok
end

-- ── confirmation state ────────────────────────────────────────────────────────
local pending = { action = nil, path = nil, timer = nil, overlay = nil }

local function cancel_pending()
    if pending.timer   then pending.timer:kill() end
    if pending.overlay then pending.overlay:remove() end
    pending.action  = nil
    pending.path    = nil
    pending.timer   = nil
    pending.overlay = nil
end

mp.register_event('seek',        cancel_pending)
mp.register_event('file-loaded', cancel_pending)

-- ── trash ─────────────────────────────────────────────────────────────────────
local function do_trash(path)
    local name = path:match('[^/\\]+$') or path
    navigate_away()
    local ok = false

    if platform == 'windows' then
        local ps = string.format(
            "Add-Type -AssemblyName Microsoft.VisualBasic; " ..
            "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(" ..
            "'%s', 'OnlyErrorDialogs', 'SendToRecycleBin')",
            ps_sq(path))
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'powershell', '-NoProfile', '-NonInteractive', '-Command', ps},
        })
        ok = res.status == 0

    elseif platform == 'darwin' then
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'osascript', '-e', string.format(
                'tell application "Finder" to move POSIX file %q to trash', path)},
        })
        ok = res.status == 0

    else
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'gio', 'trash', '--', path},
        })
        if res.status ~= 0 then
            res = mp.command_native({
                name = 'subprocess', playback_only = false,
                args = {'trash-put', '--', path},
            })
        end
        ok = res.status == 0
    end

    if ok then
        push_undo(path)
        simple_osd('Moved to trash: ' .. name .. '\n(Ctrl+Z to undo)', 4)
    else
        simple_osd('Could not trash: ' .. name)
    end
end

-- ── permanent delete ──────────────────────────────────────────────────────────
local function do_delete(path)
    local name = path:match('[^/\\]+$') or path
    navigate_away()
    local ok, err = os.remove(path)
    simple_osd(ok and ('Deleted permanently: ' .. name)
                   or ('Could not delete: ' .. name .. ' (' .. (err or '?') .. ')'))
end

-- ── undo ──────────────────────────────────────────────────────────────────────
local function do_undo()
    if #undo_stack == 0 then
        simple_osd('Nothing to undo.', 2)
        return
    end
    local path = table.remove(undo_stack)
    local name = path:match('[^/\\]+$') or path
    local ok   = restore_from_trash(path)
    if ok then
        simple_osd('Restored: ' .. name ..
            (#undo_stack > 0 and ('\n(' .. #undo_stack .. ' more undo(s) available)') or ''), 4)
    else
        table.insert(undo_stack, path)
        simple_osd('Could not restore: ' .. name ..
            '\n(was the Recycle Bin emptied?)', 4)
    end
end

-- ── arm / confirm logic ───────────────────────────────────────────────────────
local CONFIRM_SECS = 5

local function handle_key(action_type)
    local path = get_local_path()
    if not path then simple_osd('Not a local file', 2); return end

    local name = path:match('[^/\\]+$') or path

    if pending.action == action_type and pending.path == path then
        cancel_pending()
        if action_type == 'trash' then do_trash(path) else do_delete(path) end
        return
    end

    cancel_pending()
    pending.action  = action_type
    pending.path    = path
    pending.overlay = make_overlay(action_type, name, CONFIRM_SECS)

    pending.timer = mp.add_timeout(CONFIRM_SECS, function()
        cancel_pending()
        simple_osd('Cancelled.', 2)
    end)
end

-- ── bindings ──────────────────────────────────────────────────────────────────
mp.add_forced_key_binding('DEL',       'trash-current-file',    function() handle_key('trash')  end)
mp.add_forced_key_binding('Shift+DEL', 'delete-file-permanent', function() handle_key('delete') end)
mp.add_forced_key_binding('ctrl+z',    'undo-trash',            do_undo)