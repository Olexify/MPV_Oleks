-- sort-playlist.lua  ── place in your mpv/scripts/ folder ──────────────────
--
-- Automatically sorts the playlist to match Windows Explorer's current sort
-- order when a new folder is opened.
-- Alt+S → manually cycle through sort modes at any time.
--
-- ── CONFIG ────────────────────────────────────────────────────────────────────
local AUTO_SORT    = -1  -- -1 = auto-detect from open Explorer window
                         --  0 = disabled (manual Alt+S only)
                         --  1 = always Name A→Z
                         --  2 = always Name Z→A
                         --  3 = always Date newest first
                         --  4 = always Date oldest first
local DEFAULT_SORT =  1  -- fallback when Explorer detection fails (Name A→Z)
-- ─────────────────────────────────────────────────────────────────────────────

local mp    = require('mp')
local utils = require('mp.utils')

local MODES = {
    { label = 'Name  A → Z',        key = 'name', rev = false },
    { label = 'Name  Z → A',        key = 'name', rev = true  },
    { label = 'Date  newest first',  key = 'date', rev = true  },
    { label = 'Date  oldest first',  key = 'date', rev = false },
}
local current_mode = DEFAULT_SORT
local last_dir     = nil
local auto_timer   = nil
local platform     = mp.get_property_native('platform')

-- ── helpers ───────────────────────────────────────────────────────────────────
local function full_path(p)
    if not p or p == '' then return '' end
    if platform == 'windows' then
        if p:match('^%a:[/\\]') or p:match('^\\\\') then return p end
    else
        if p:match('^/') then return p end
    end
    return utils.join_path(mp.get_property('working-directory', ''), p)
end

local function get_mtimes(filenames)
    local mtimes = {}
    if #filenames == 0 then return mtimes end
    if platform == 'windows' then
        local parts = {}
        for _, fn in ipairs(filenames) do
            table.insert(parts, "'" .. full_path(fn):gsub("'", "''") .. "'")
        end
        local ps = string.format(
            'foreach($f in @(%s)){try{[int64]([System.IO.File]::' ..
            'GetLastWriteTimeUtc($f)-[datetime]"1970-01-01").TotalSeconds}catch{Write-Output 0}}',
            table.concat(parts, ','))
        local res = mp.command_native({
            name = 'subprocess', playback_only = false, capture_stdout = true,
            args = {'powershell', '-NoProfile', '-NonInteractive', '-Command', ps}
        })
        if res and res.status == 0 and res.stdout then
            local i = 1
            for t in res.stdout:gmatch('[0-9]+') do
                if filenames[i] then mtimes[filenames[i]] = tonumber(t) or 0; i = i + 1 end
            end
        end
    else
        local flag = platform == 'darwin' and '-f' or '-c'
        local fmt  = platform == 'darwin' and '%m'  or '%Y'
        local args = {'/usr/bin/stat', flag, fmt}
        for _, fn in ipairs(filenames) do table.insert(args, full_path(fn)) end
        local res = mp.command_native({
            name = 'subprocess', playback_only = false, capture_stdout = true, args = args
        })
        if res and res.status == 0 and res.stdout then
            local i = 1
            for t in res.stdout:gmatch('[0-9]+') do
                if filenames[i] then mtimes[filenames[i]] = tonumber(t) or 0; i = i + 1 end
            end
        end
    end
    return mtimes
end

-- in-place reorder via playlist-move (no file reload, no playback interruption)
local function apply_sort(sorted_fns, pos_of)
    for target = 0, #sorted_fns - 1 do
        local fn   = sorted_fns[target + 1]
        local from = pos_of[fn]
        if from == nil then goto continue end
        if from ~= target then
            if from > target then
                mp.commandv('playlist-move', from, target)
                for f, p in pairs(pos_of) do
                    if p >= target and p < from then pos_of[f] = p + 1 end
                end
            else
                mp.commandv('playlist-move', from, target + 1)
                for f, p in pairs(pos_of) do
                    if p > from and p <= target then pos_of[f] = p - 1 end
                end
            end
            pos_of[fn] = target
        end
        ::continue::
    end
end

-- ── detect sort from open Explorer window (Windows only) ─────────────────────
-- PROPERTYKEY mapping (FMTID_Storage = B725F130...):
--   propid 10 = System.ItemNameDisplay  (Name column)
--   propid 14 = System.DateModified     (Date modified column)
--   direction  1 = ascending,  -1 = descending

local function detect_explorer_sort(folder_path)
    if platform ~= 'windows' then return nil end
    local safe = folder_path:gsub("'", "''"):gsub('/', '\\')
    local ps = string.format([[
$target = '%s'
$shell  = New-Object -ComObject Shell.Application
foreach ($w in @($shell.Windows())) {
    try {
        $p = $w.Document.Folder.Self.Path
        if ([string]::Equals($p, $target, 'OrdinalIgnoreCase')) {
            $cols = $w.Document.SortColumns
            if ($cols -ne $null -and @($cols).Count -gt 0) {
                $c     = @($cols)[0]
                $fmtid = $c.propkey.fmtid.ToString()
                $pid_v = $c.propkey.pid
                $dir   = $c.direction
                Write-Output "${fmtid}|${pid_v}|${dir}"
            }
            break
        }
    } catch {}
}
]], safe)
    local res = mp.command_native({
        name = 'subprocess', playback_only = false, capture_stdout = true,
        args = {'powershell', '-NoProfile', '-NonInteractive', '-Command', ps}
    })
    if not res or res.status ~= 0 then return nil end
    local out = res.stdout or ''
    if out:match('^%s*$') then return nil end
    local _, propid, direction = out:match('^([^|]+)|(%d+)|(-?%d+)')
    if not propid then return nil end
    propid    = tonumber(propid)
    direction = tonumber(direction)
    if propid == 10 then                         -- Name column
        return direction >= 0 and 1 or 2
    elseif propid == 14 or propid == 15 then     -- Date modified / Date created
        return direction < 0 and 3 or 4
    end
    return nil  -- unsupported column → caller uses fallback
end

-- ── core sort function ────────────────────────────────────────────────────────
local function sort_playlist(show_osd)
    local mode     = MODES[current_mode]
    local playlist = mp.get_property_native('playlist')
    if not playlist or #playlist < 2 then
        if show_osd then mp.osd_message('Nothing to sort (< 2 entries)', 2) end
        return
    end
    local current_path = mp.get_property('path', '')
    local filenames, pos_of = {}, {}
    for i, entry in ipairs(playlist) do
        table.insert(filenames, entry.filename)
        pos_of[entry.filename] = i - 1
    end
    local mtimes = (mode.key == 'date') and get_mtimes(filenames) or {}
    local items = {}
    for _, fn in ipairs(filenames) do
        local fp   = full_path(fn)
        local name = (fp:match('[^/\\]+$') or fp):lower()
        table.insert(items, { filename = fn, name = name, date = mtimes[fn] or 0 })
    end
    table.sort(items, function(a, b)
        local av, bv = a[mode.key], b[mode.key]
        if av == bv then return a.name < b.name end
        return mode.rev and (av > bv) or (av < bv)
    end)
    local sorted = {}
    for _, item in ipairs(items) do table.insert(sorted, item.filename) end
    apply_sort(sorted, pos_of)
    local new_pos = pos_of[current_path]
    if new_pos then mp.set_property_number('playlist-pos', new_pos) end
    if show_osd then mp.osd_message('Sort: ' .. mode.label, 3) end
end

-- ── auto-sort on new folder ───────────────────────────────────────────────────
local function on_file_loaded()
    if AUTO_SORT == 0 then return end
    local path = mp.get_property('path', '')
    local dir  = path:match('^(.+)[/\\][^/\\]+$') or ''
    if dir == last_dir then return end
    last_dir = dir
    if auto_timer then auto_timer:kill() end
    auto_timer = mp.add_timeout(0.5, function()
        auto_timer = nil
        local mode
        if AUTO_SORT == -1 then
            mode = detect_explorer_sort(dir) or DEFAULT_SORT
        else
            mode = AUTO_SORT
        end
        current_mode = mode
        sort_playlist(true)
    end)
end

mp.register_event('file-loaded', on_file_loaded)

-- ── manual Alt+S ─────────────────────────────────────────────────────────────
mp.add_key_binding('Alt+s', 'cycle-sort-mode', function()
    current_mode = (current_mode % #MODES) + 1
    sort_playlist(true)
end)