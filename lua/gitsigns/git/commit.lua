local FORMATS = {
  full = table.concat({
    'commit' .. '%x20%H',
    'tree' .. '%x20%T',
    'parent' .. '%x20%P',
    'author' .. '%x20%an%x20<%ae>%x20%ad',
    'committer' .. '%x20%cn%x20<%ce>%x20%cd',
    'encoding' .. '%x20%e',
    '',
    '%B',
  }, '%n'),
  message = '%P%n%h %s%nAuthor: %an <%ae>%nDate:   %aI%n%n%B',
}

--- Read a full commit with its patch, or just its metadata and message.
--- @async
--- @param repo Gitsigns.Repo
--- @param revision string
--- @param kind 'full'|'message'
--- @return string[] lines
--- @return string? parent First parent, returned for message reads.
return function(repo, revision, kind)
  local lines, err, code = repo:command({
    'show',
    kind == 'message' and '--no-patch' or '--unified=0',
    '--no-show-signature',
    '--encoding=UTF-8',
    '--format=format:' .. FORMATS[kind],
    revision,
    '--',
  }, { ignore_error = true })
  if code ~= 0 then
    error(err or 'Unable to read commit', 0)
  end

  if kind == 'message' then
    local parent = table.remove(lines, 1):match('^(%x+)')
    if lines[#lines] == '' then
      table.remove(lines)
    end
    return lines, parent
  end

  -- Remove encoding line if it's not set to something meaningful.
  if assert(lines[6]):match('^encoding (unknown)?') == nil then
    table.remove(lines, 6)
  end
  return lines
end
