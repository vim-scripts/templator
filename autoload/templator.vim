" @Author:      Tom Link (mailto:micathom AT gmail com?subject=[vim])
" @License:     GPL (see http://www.gnu.org/licenses/gpl.txt)
" @Last Change: 2012-12-13.
" @Revision:    314


if !exists('g:templator#verbose')
    " If true, show some warnings (e.g. when opening an already existing 
    " file that wasn't created by templator).
    let g:templator#verbose = 1   "{{{2
endif


if !exists('g:templator#hooks')
    " :nodoc:
    let g:templator#hooks = {}   "{{{2
endif


if !exists('g:templator#edit_new')
    " The command used for editing newly created files.
    let g:templator#edit_new = 'hide edit'   "{{{2
endif


if !exists('g:templator#edit_again')
    " The command used for editing files that already existed.
    " If empty, don't open already existing files.
    let g:templator#edit_again = g:templator#edit_new   "{{{2
endif


if !exists('g:templator#sep')
    let g:templator#sep = exists('+shellslash') && !&shellslash ? '\' : '/'    "{{{2
endif


let s:expanders_init = {}


" :nodoc:
function! templator#Complete(ArgLead, CmdLine, CursorPos) "{{{3
    let templators = keys(s:GetAllTemplators())
    " TLogVAR templators
    let dir = fnamemodify(a:ArgLead, ':h')
    let base = fnamemodify(a:ArgLead, ':t')
    let templators = filter(templators, 'strpart(v:val, 0, len(a:ArgLead)) ==# base')
    if empty(templators)
        let completions = split(glob(a:ArgLead .'*'), '\n')
    else
        let completions = map(templators, 's:JoinFilename(dir, v:val)')
    endif
    " TLogVAR completions
    return completions
endf


" Create files based on the template set referred to by the basename of 
" the name argument.
function! templator#Setup(name, ...) "{{{3
    let args = s:ParseArgs(a:000)
    let [tname, dirname] = s:GetDirname(a:name)
    " TLogVAR dirname
    let templator = s:GetTemplator(tname)
    if !s:RunHook('', tname, 'CheckArgs', args, 1)
        throw 'templator#Setup: Invalid arguments for template set '. string(tname) .': '. string(a:000)
    endif
    let ttype = templator.type
    let cwd = getcwd()
    " TLogVAR cwd
    try
        " TLogVAR templator.dir
        let templator_dir_len = len(templator.dir) + 1
        if templator.dir =~ '[\/]$'
            let templator_dir_len += 1
        endif
        call s:RunHook(dirname, tname, 'Before', args)
        let includefilename_args = copy(args)
        for filename in templator.files
            let outfile = s:GetOutfile(dirname, filename, args, templator_dir_len)
            let includefilename_args['__FILE__'] = filename
            let includefilename_args['__FILENAME__'] = outfile
            if s:RunHook('', tname, 'IncludeFilename', includefilename_args, 1)
                call s:SetDir(dirname)
                " TLogVAR filename
                if filereadable(outfile)
                    if g:templator#verbose
                        echohl WarningMsg
                        echom "Templator: File already exists: " outfile
                        echohl NONE
                    endif
                    if !empty(g:templator#edit_again)
                        exec g:templator#edit_again fnameescape(outfile)
                        let b:noquickfixsigns = 1
                    endif
                else
                    let lines = readfile(filename)
                    if writefile(lines, outfile) != -1
                        let fargs = copy(args)
                        let fargs.filename = outfile
                        if !s:RunHook('', tname, 'Edit', args)
                            exec g:templator#edit_new fnameescape(outfile)
                        endif
                        let b:noquickfixsigns = 1
                        let b:templator_args = args
                        call templator#expander#{ttype}#Expand()
                        call s:RunHook(&acd ? '' : expand('%:p:h'), tname, 'Buffer', args)
                        unlet! b:templator_args
                        update
                    endif
                endif
            endif
            unlet! b:noquickfixsigns
        endfor
        call s:RunHook(dirname, tname, 'After', args)
    finally
        exec 'cd' fnameescape(cwd)
    endtry
endf


function! s:GetAllTemplators() "{{{3
    if !exists('s:templators')
        let files = globpath(&rtp, 'templator/*.*')
        let s:templators = {}
        for dirname in split(files, '\n')
            if isdirectory(dirname)
                let tname = fnamemodify(dirname, ':t:r')
                let ttype = fnamemodify(dirname, ':e')
                " TLogVAR ttype, tname
                if !has_key(s:expanders_init, ttype)
                    try
                        let s:expanders_init[ttype] = templator#expander#{ttype}#Init()
                    catch /^Vim\%((\a\+)\)\=:E117/
                        let s:expanders_init[ttype] = 0
                    endtry
                endif
                " echom "DBG get(s:expanders_init, ttype, 0)" get(s:expanders_init, ttype, 0)
                if get(s:expanders_init, ttype, 0)
                    if has_key(s:templators, tname)
                        if g:templator#verbose
                            echohl WarningMsg
                            echom "Templator: duplicate entry:" tname filename
                            echohl NONE
                        endif
                    else
                        let dirname_len = len(dirname)
                        let filenames = split(glob(dirname .'/**/*'), '\n')
                        let filenames = filter(filenames, '!isdirectory(v:val)')
                        let s:templators[tname] = {
                                    \ 'type': ttype,
                                    \ 'dir': dirname,
                                    \ 'files': filenames
                                    \ }
                    endif
                endif
            endif
        endfor
    endif
    return s:templators
endf


function! s:GetDirname(name) "{{{3
    " TLogVAR a:name
    if a:name =~ '^\*'
        let use_root = 1
        let name = strpart(a:name, 1)
    else
        let use_root = 0
        let name = a:name
    endif
    let dirname = fnamemodify(name, ':h')
    let tname = fnamemodify(name, ':t')
    " TLogVAR use_root, name, dirname, tname
    if use_root
        if exists('b:templator_root_dir')
            let dirname = s:JoinFilename(b:templator_root_dir, dirname)
        elseif exists('g:loaded_tlib') && g:loaded_tlib >= 100
            let [vcs_type, vcs_dir] = tlib#vcs#FindVCS(expand('%'))
            " TLogVAR vcs_type, vcs_dir
            if !empty(vcs_dir)
                let dirname = s:JoinFilename(fnamemodify(vcs_dir, ':p:h:h'), dirname)
            endif
        else
            echohl WarningMsg
            echom "Templator: No method left to find the project's root directory:" a:name
            echohl NONE
        endif
    endif
    " TLogVAR dirname
    let dirname = fnamemodify(dirname, ':p')
    if !isdirectory(dirname)
        call mkdir(dirname, 'p')
    endif
    " TLogVAR tname, dirname
    return [tname, dirname]
endf


function! s:GetTemplator(tname) "{{{3
    let templators = s:GetAllTemplators()
    if !has_key(templators, a:tname)
        throw "Templator: Unknown template name: ". a:tname
    endif
    let templator = templators[a:tname]
    let ttype = templator.type
    if !get(s:expanders_init, ttype, 0)
        throw printf("Templator: Unsupported template type %s for %s", ttype, a:name)
    endif
    if !has_key(g:templator#hooks, ttype)
        let g:templator#hooks[a:tname] = {}
        let hooks_file = fnamemodify(templator.dir, ':p:h:r') .'.vim'
        " TLogVAR hooks_file, filereadable(hooks_file)
        if filereadable(hooks_file)
            exec 'source' fnameescape(hooks_file)
        endif
    endif
    return templator
endf


function! s:GetOutfile(dirname, filename, args, templator_dir_len) "{{{3
    " TLogVAR a:dirname, a:filename, a:args, a:templator_dir_len
    let subdir = strpart(fnamemodify(a:filename, ':h'), a:templator_dir_len)
    " TLogVAR subdir
    let subfilename = s:ExpandFilename(fnamemodify(a:filename, ':t'), a:args)
    " TLogVAR subfilename
    let outdir = a:dirname
    if !empty(subdir)
        let subdir = s:ExpandFilename(subdir, a:args)
        if outdir == '.'
            let outdir = subdir
        else
            let outdir = s:JoinFilename(outdir, subdir)
        endif
    endif
    " TLogVAR outdir
    if outdir == '.'
        let outfile = subfilename
    else
        if !isdirectory(outdir)
            call mkdir(outdir, 'p')
        endif
        let outfile = s:JoinFilename(outdir, subfilename)
    endif
    " TLogVAR outfile
    return outfile
endf


function! s:RunHook(dirname, tname, name, args, ...) "{{{3
    " TLogVAR a:dirname, a:tname, a:name, a:args
    if a:0 >= 1
        let default_value = a:1
        let return_success = 0
    else
        let return_success = 1
    endif
    if !has_key(g:templator#hooks, a:tname)
        throw 'No hooks defined for template '. a:tname .' ('. join(keys(g:templator#hooks)) .')'
    endif
    let tdef = g:templator#hooks[a:tname]
    " TLogVAR tdef
    if has_key(tdef, a:name)
        if !empty(a:dirname)
            let cwd = getcwd()
        endif
        try
            call s:SetDir(a:dirname)
            " TLogVAR tdef[a:name]
            let return_value = tdef[a:name](a:args)
            if return_success
                return 1
            else
                return return_value
            endif
        finally
            if !empty(a:dirname)
                exec 'cd' fnameescape(cwd)
            endif
        endtry
    endif
    return return_success ? 0 : default_value
endf


function! s:SetDir(dirname) "{{{3
    let dirname = s:StripSep(a:dirname)
    " TLogVAR dirname, getcwd()
    if !empty(dirname) && getcwd() != dirname
        exec 'cd' fnameescape(dirname)
    endif
endf


function! s:ExpandFilename(filename, args) "{{{3
    let filename = substitute(a:filename, '\$\(\$\|{\(\w\+\)\%(=\(.\{-}\)\)\?}\)', '\=s:PlaceHolder(a:args, submatch(1), submatch(2), submatch(3))', 'g')
    return filename
endf


function! s:PlaceHolder(args, pct, name, default) "{{{3
    if a:pct == '$'
        return '$'
    else
        return get(a:args, a:name, a:default)
    endif
endf


function! s:ParseArgs(arglist) "{{{3
    let args = {}
    let idx = 1
    for arg in a:arglist
        if arg =~ '^\w\+='
            let key = matchstr(arg, '^\w\{-}\ze=')
            let val = matchstr(arg, '^\w\{-}=\zs.*$')
        else
            let key = idx
            let val = arg
            let idx += 1
        endif
        let args[key] = val
    endfor
    return args
endf


function! s:JoinFilename(...) "{{{3
    let parts = map(copy(a:000), 's:StripSep(v:val)')
    return join(parts, g:templator#sep)
endf


function! s:StripSep(filename) "{{{3
    return substitute(a:filename, '[\/]$', '', 'g')
endf

