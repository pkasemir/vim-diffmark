function! DiffMarkError(msg)
	try
		throw a:msg
	catch
		let throwpoint = substitute(v:throwpoint, '\[\(\d\+\)\]\.\.DiffMarkError,.*', ', Line \1', '')
		echohl ErrorMsg
		let error_msg = "DiffMark Error: " . a:msg
		echomsg error_msg
		call DiffMarkDebug(error_msg)
		echohl None
		let tb_msg = "    From: " . throwpoint
		echomsg tb_msg
		call DiffMarkDebug(tb_msg)
	endtry
endfunction

function! DiffMarkDebug(msg)
	if !g:diffmark_debug
		return
	endif
	let my_window = winnr()
	let debug_buf_name = "-= DiffMark Debug =-"
	let debug_buf = bufnr(debug_buf_name, 1)
	let debug_window = bufwinid(debug_buf_name)
	if debug_window == -1
		bot 10new
		if debug_buf == -1
			exe "setlocal bt=nofile bh=hide noswf ro ft="
			exe "file " . debug_buf_name
		else
			exe "buf " . debug_buf
		endif
		exe "match Error /^DiffMark Error:.*/"
		exe my_window . "wincmd w"
		let debug_window = bufwinid(debug_buf_name)
	endif
	call appendbufline(debug_buf_name, "$", a:msg)
	call win_execute(debug_window, "normal G")

endfunction

function! DiffMarkCatFile(last_line, line, file)
	if a:last_line == a:line
		return "<(printf '')"
	else
		return "<(sed -n '" . a:last_line . "," . (a:line - 1) . "p' " . a:file . ")"
	endif
endfunction

function! DiffMarkImpl()
	let opt = "-a --binary "
	if &diffopt =~ "icase"
		let opt = opt . "-i "
	endif
	if &diffopt =~ "iwhite"
		let opt = opt . "-b "
	endif

	let md5sum_in = system("cat ". v:fname_in . " | md5sum")
	let md5sum_new = system("cat ". v:fname_new . " | md5sum")
	let f_in = v:fname_in
	let f_new = v:fname_new
	let marks_in = get(g:diffmarks, md5sum_in, [])
	let marks_new = get(g:diffmarks, md5sum_new, [])
	if marks_in != [] && marks_new != []
		let last_nr_in = 0
		let last_nr_new = 0
		let both_marks = []
		for mark_in in marks_in
			for mark_new in marks_new
				if mark_in.mark == mark_new.mark
					if mark_in.nr <= last_nr_in
						break
					endif
					if mark_new.nr <= last_nr_new
						break
					endif
					let last_nr_in = mark_in.nr
					let last_nr_new = mark_new.nr
					call add(both_marks, {"in": mark_in, "new": mark_new})
					break
				endif
			endfor
		endfor
		let last_nr_in = 0
		let last_nr_new = 0
		silent execute "!printf '' > " . v:fname_out
		for marks in both_marks
			let linenr_in = marks.in.nr
			let linenr_new = marks.new.nr
			let f_in = DiffMarkCatFile(last_nr_in + 1, linenr_in, v:fname_in)
			let f_new = DiffMarkCatFile(last_nr_new + 1, linenr_new, v:fname_new)
			silent execute "!diff " . opt . f_in . " " . f_new .
				\ " | gawk -v off1=" . last_nr_in . " -v off2=" . last_nr_new . " '".
				\ "{ if (match($0, /^([0-9]+)(,([0-9]+))?([acd])([0-9]+)(,([0-9]+))?/, grp)) {" .
				\ "    range1=\"\"; range2=\"\";" .
				\ "    if (grp[3] \\!= \"\") range1=\",\" grp[3]+off1;" .
				\ "    if (grp[7] \\!= \"\") range2=\",\" grp[7]+off2;" .
				\ "    print  grp[1]+off1 range1 grp[4] grp[5]+off2 range2;" .
				\ "  } else { print }" .
				\ "}' >> " . v:fname_out
			if marks.in.line != marks.new.line
				if g:diffmark_force_align == ""
					echo "DiffMark Warning: marked lines are not equal, alignment may not work"
					"echo marks.in
					"echo marks.new
					echo "  Press (f) to force alignment. Diff will not show for marked lines."
					if nr2char(getchar()) ==? "f"
						let g:diffmark_force_align = "force"
					else
						let g:diffmark_force_align = "diff"
					endif
				endif
				if g:diffmark_force_align == "diff"
					silent execute "!echo '" . linenr_in . "c" . linenr_new . "' >> " . v:fname_out
				endif
			endif
			let last_nr_in = linenr_in
			let last_nr_new = linenr_new
		endfor
	else
		silent execute "!diff " . opt . f_in . " " . f_new . " > " . v:fname_out
	endif
endfunction

function! DiffMarkGather(mark_names)
	if &diff
		let marks = []
		for mark in a:mark_names
			let nr = line("'" . mark)
			if nr == 0 || nr > line('$')
				continue
			endif
			call add(marks, {"mark": mark, "nr": nr, "line": getline(nr)})
		endfor
		if len(marks) == 0
			return
		endif
		call add(marks, {"mark": "EOF", "nr": line('$') + 1, "line": ""})
		let tmp = tempname()
		execute "write! " . tmp
		let md5sum = system("cat ". tmp . " | md5sum")
		call delete(tmp)
		call extend(g:diffmarks, {l:md5sum : marks})
	endif
endfunction

function! s:DiffMark(mark_args)
	let shell_change = &shell !~ "bash$"
	if shell_change
		let shell_save = &shell
		let shell_bash = split(system("which bash 2>/dev/null"))
		if len(shell_bash) == 0
			call DiffMarkError("requires bash!")
			return
		endif
		let &shell = shell_bash[0]
	endif
	let diffexpr_save = &diffexpr
	set diffexpr=DiffMarkImpl()
	let g:diffmark_force_align = ""
	let g:diffmarks = {}
	let g:diffmark_debug = 0
	let mark_names = []
	if len(a:mark_args) > 0
		let mark_names = deepcopy(a:mark_args)
		call filter(mark_names, 'len(v:val) == 1')
	endif
	if len(mark_names) == 0
		let mark_names = ['a']
	endif
	let orig_win = winnr()
	windo call DiffMarkGather(mark_names)
	execute orig_win . "wincmd w"
	"echo g:diffmarks
	"call getchar()
	diffupdate
	let &diffexpr = diffexpr_save
	redraw!
	if shell_change
		let &shell = shell_save
	endif
endfunction
com! -narg=* DiffMark call s:DiffMark([<f-args>])

function! s:DiffSelf(mark_args)
	let mark_names_real = []
	let mark_names_diff = []

	let apply_to_real = 1
	for mark in a:mark_args
		if len(mark) != 1
			continue
		endif
		if mark == ","
			let apply_to_real = 0
			continue
		endif
		if apply_to_real
			call add(mark_names_real, mark)
		else
			call add(mark_names_diff, mark)
		endif
	endfor
	if len(mark_names_real) == 0
		let mark_names_real = ['a', 'b']
	endif
	if len(mark_names_diff) == 0
		let mark_names_diff = ['c', 'd']
	endif
	if len(mark_names_real) > len(mark_names_diff)
		let mark_names_real = mark_names_real[0:len(mark_names_diff) - 1]
	endif
	if len(mark_names_diff) > len(mark_names_real)
		let mark_names_diff = mark_names_diff[0:len(mark_names_real) - 1]
	endif

	let g:diffmarks = {}
	diffthis
	call DiffMarkGather(mark_names_diff)

	let filetype = &ft
	let lines = getline(1, "$")
	vnew
	call append("$", lines)
	exe "setlocal bt=nofile bh=wipe nobl noswf ro ft=" . filetype
	exe "file " . expand("#") . ".DiffSelf"
	let mark_index = 0
	for marks in values(g:diffmarks)
		for mark in marks
			if mark.mark == "EOF"
				break
			endif
			exe "keepjumps normal " . (mark.nr + 1) . "ggm" . mark_names_real[mark_index]
			let mark_index += 1
		endfor
	endfor

	diffthis
	call s:DiffMark(mark_names_real)

endfunction
com! -narg=* DiffSelf call s:DiffSelf([<f-args>])

func! s:MyRange(r, ...) range
	echo "MyRange ". a:firstline . " " . a:lastline. " " . a:r
	echo "0 " . a:0
	echo "1 " . a:1
endfunction
com! -range MyRange <line1>,<line2>call s:MyRange(<range>, "help", 5)
