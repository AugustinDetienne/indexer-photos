-- Indexer photos — double-clic : choisir un dossier ; ou glisser des dossiers sur l'icône.

on run
	set leDossier to choose folder with prompt "Dossier de photos à indexer :"
	lancer({leDossier})
end run

on open lesElements
	lancer(lesElements)
end open

on lancer(lesDossiers)
	set noms to ""
	repeat with d in lesDossiers
		set noms to noms & "• " & (POSIX path of d) & return
	end repeat

	display dialog "Indexer ces dossiers ?" & return & return & noms & return & ¬
		"Les mots-clés seront ÉCRITS dans les fichiers (JPG, TIFF, DNG) et dans des .xmp à côté des RAW." & return & ¬
		"Vérifie qu'une sauvegarde existe." buttons {"Annuler", "Lancer"} ¬
		default button "Lancer" cancel button "Annuler" with icon caution

	set cmd to "bash ~/photo_indexer/run_indexer.sh"
	repeat with d in lesDossiers
		set cmd to cmd & " " & quoted form of (POSIX path of d)
	end repeat

	tell application "Terminal"
		activate
		do script cmd
	end tell
end lancer
