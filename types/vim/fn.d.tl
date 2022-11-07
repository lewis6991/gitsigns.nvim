local record M
  bufexists: function(string): integer
  bufnr: function(string): integer
  iconv: function(string, string, string): string
  line: function(string): integer
  join: function({any}, string): string
  getpos: function(string): {integer}
  executable: function(string): integer
  exists: function(string): integer
  expand: function(string): string
  foldclosed: function(integer): integer
  foldclosedend: function(integer): integer
  getcwd: function(): string
  input: function(string, string): string

  ['repeat#set']: function(string, integer)

  record QFItem
    bufnr: integer
    filename: string
    lnum: integer
    nr: integer
    text: string
    type: string
  end

  record QFWhat
    context: any
    efm: string
    id: integer
    idx: integer
    items: {QFItem}
    lines: {string}
    nr: integer
    quickfixtextfunc: string
    title: string
  end

  setqflist: function(list: {QFItem}, action: string, what: QFWhat)
  setloclist: function(nr: integer, list: {QFItem}, action: string, what: QFWhat)

  sign_unplace: function(string, {string:any})
  sign_place: function(number, string, string, string | number, {string:any})

  record SignPlaceItem
    buffer: integer
    group: string
    id: integer
    lnum: integer
    name: string
    priority: integer
  end
  sign_placelist: function({SignPlaceItem})
  sign_getdefined: function(string): table

  record SignPlacedInfo
    bufnr: integer
    record SignPlacedSigns
      id: integer
      name: string
      group: string
      lnum: integer
      priority: integer
    end
    signs: {SignPlacedSigns}
  end
  sign_getplaced: function(integer, table): {SignPlacedInfo}

  sign_define: function(string, table): number
  sign_undefine: function(string): number
  strdisplaywidth: function(string, integer): integer
  stridx: function(haystack: string, needle: string, start: integer): integer
  string: function(any): string
  systemlist: function({string}): {string}
  tempname: function(): string
  type: function(any): integer

  FugitiveReal: function(...: any): string
  FugitiveParse: function(...: any): {string, string}

  record WinInfo
    textoff: integer
  end
  getwininfo: function(integer): {WinInfo}
end

return M
