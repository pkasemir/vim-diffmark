function! DiffMarkDiff(top_of_file, line, file)
	if a:top_of_file
		return "<(head -n ". (a:line - 1) . " " . a:file . ")"
	else
		let lines = "1,". (a:line - 1) . " "
		if a:line <= 1
			let lines = ""
		endif
		return "<(echo ; tail -n +". (a:line + 1) . " " . a:file . ")"
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
	let mark_in = get(g:diffmarks, md5sum_in, {})
	let mark_new = get(g:diffmarks, md5sum_new, {})
	let linenr_in = get(mark_in, "nr", 0)
	let linenr_new = get(mark_new, "nr", 0)
	if linenr_in > 0 && linenr_new > 0
		let line_in = get(mark_in, "line", 0)
		let line_new = get(mark_new, "line", 0)
		let f_in = DiffMarkDiff(v:true, linenr_in, v:fname_in)
		let f_new = DiffMarkDiff(v:true, linenr_new, v:fname_new)
		silent execute "!diff " . opt . f_in . " " . f_new . " > " . v:fname_out
		if line_in != line_new
			echo "DiffMark Warning: marked lines are not equal, diff may not work"
			echo "  Press (f) to force alignment. Diff will not show for marked lines."
			if nr2char(getchar()) !=? "f"
				silent execute "!echo '" . linenr_in . "c" . linenr_new ."' >> " . v:fname_out
			endif
		endif
		let f_in = DiffMarkDiff(v:false, linenr_in, v:fname_in)
		let f_new = DiffMarkDiff(v:false, linenr_new, v:fname_new)
		silent execute "!diff " . opt . f_in . " " . f_new .
			\ " | gawk -v f1=" . (linenr_in - 1) . " -v f2=" . (linenr_new - 1) . " '".
			\ "{ if (match($0, /^([0-9]+)(,([0-9]+))?([acd])([0-9]+)(,([0-9]+))?/, grp)) {" .
			\ "    com1=\"\"; com2=\"\";" .
			\ "    if (grp[3] \\!= \"\") com1=\",\" grp[3]+f1;" .
			\ "    if (grp[7] \\!= \"\") com2=\",\" grp[7]+f2;" .
	       		\ "    print  grp[1]+f1 com1 grp[4] grp[5]+f2 com2;" .
			\ "  } else { print }" .
			\ "}' >> " . v:fname_out
	else
		silent execute "!diff " . opt . f_in . " " . f_new . " > " . v:fname_out
	endif


endfunction
function! DiffMarkGather()
	if &diff
		let linenr = getpos("'a")[1]
		let tmp = tempname()
		execute "write! " . tmp
		let md5sum = system("cat ". tmp . " | md5sum")
		call delete(tmp)
		call extend(g:diffmarks, {l:md5sum : 
			\ {"nr": linenr, "line": getline(linenr)}})
	endif
endfunction
function! s:DiffMark()
	let diffexpr_save = &diffexpr
	set diffexpr=DiffMarkImpl()
	let g:diffmarks = {}
	windo call DiffMarkGather()
	diffupdate
	let &diffexpr = diffexpr_save
	redraw!
endfunction
com! DiffMark call s:DiffMark()

func! s:MyRange(r, ...) range
	echo "MyRange ". a:firstline . " " . a:lastline. " " . a:r
	echo "0 " . a:0
	echo "1 " . a:1
endfunction
com! -range MyRange <line1>,<line2>call s:MyRange(<range>, "help", 5)
