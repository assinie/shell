MODULE = 'y'
;WITH_SDCARD_FOR_ROOT = 'y'
;LS_VERBOSE = 'y'
;LS_VERBOSE_DATE = 'y'
;LS_VERBOSE_ATTRIBUTE = 'y'
;LS_VERBOSE_SIZE = 'y'

.ifdef MODULE
	.include "telestrat.inc"

	.include "../dependencies/kernel/src/include/kernel.inc"
	.include "../dependencies/kernel/src/include/memory.inc"
	.include "../dependencies/kernel/src/include/process.inc"

	.include "../include/bash.inc"
	.include "../include/orix.inc"

	; .code nécessaire parce que le dernier segment de orix.inc est .bss
	.code

	.macro MODULE start, end, exec
		.org $0000
		.code
		;.segment "ORIXHDR"
		;__ORIXHDR__:
		;.export __ORIXHDR__
	        .byte $01,$00               ; non-C64 marker like o65 format
	        .byte "o", "r", "i"      ; "ori" MAGIC number :$6f, $36, $35 like o65 format
	        .byte $01                ; version of this header
	cpu_mode:
	        .byte $00                ; CPU see below for description
	language_type:
	        .byte $00                   ; reserved in the future, it will define if it's a Hyperbasic file, teleass file, forth file
	        .byte $00                ; reserved
	        .byte $00                       ; reserved
	        .byte $00
	        .byte $00                   ; reserved
	        .byte $00                ; reserved
	type_of_file:
	        .byte $00
	        .word start ; loading adress
	        .word end   ; end of loading adress
	        .word exec ; starting adress
	.endmacro

	MODULE StartOfModule, EndOfModule, _ls
	;.segment "STARTUP"
	;.segment "INIT"
	;.segment "ONCE"
	.org $0801
	.code

	StartOfModule:

	.include "../lib/ch376.s"

	.include "../lib/ch376_verify.s"

	.include "../lib/get_opt.asm"
	.include "../lib/strcpy.asm"

	txt_file_not_found:
	    .asciiz "File not found :"

;	.import _cd_to_current_realpath_new
	.proc _cd_to_current_realpath_new
	    lda #<shell_bash_variables+shell_bash_struct::path_current
	    ldy #>(shell_bash_variables+shell_bash_struct::path_current+1)
	    BRK_TELEMON XOPENRELATIVE
	    rts
	.endproc

;	.proc _lowercase_char
;			cmp     #'A'
;			bcc     @skip
;			cmp     #'Z'+1
;			bcs     @skip
;			adc     #'a'-'A'
;		@skip:
;			rts
;	.endproc

.endif

.ifdef LS_VERBOSE
	NUMBER_OF_COLUMNS_LS = 1
.else
	NUMBER_OF_COLUMNS_LS = 3
.endif

.proc _ls
    lda #NUMBER_OF_COLUMNS_LS+1
    sta NUMBER_OF_COLUMNS

    jsr _ch376_verify_SetUsbPort_Mount
    ;bcc @ZZ0001
    bcs *+5
    jmp @ZZ0001

    jsr _cd_to_current_realpath_new
    ldx #$01
    jsr _orix_get_opt

    ; Potentiel buffer overflow ici
    ; Il faudrait un STRNCPY
    STRCPY ORIX_ARGV, BUFNOM

    ;MALLOC 13
    ; FIXME test OOM
    ;TEST_OOM_AND_MAX_MALLOC
    ;sta RESB
    ;sty RESB+1

    lda #<BUFEDT
    sta RESB
    lda #>BUFEDT
    sta RESB+1

    ; Potentiel buffer overflow ici
    ; Il faudrait un STRNCPY
    lda #<BUFNOM
    ldy #>BUFNOM
    sta TR2         ; TR2: Cf Match
    sty TR3
    sta RES
    sty RES+1
    jsr _strcpy

    ; RESB pointe toujours sur BUFEDT
    jsr WildCard
    bne Error       ; Il faut une autre erreur, ici c'est parce qu'il y a des caractères incorrects
    ;bcc @ZZ0002     ; Pas de '?' ni de '*'
    bcs @all

    lda BUFNOM
    bne @ZZ0002

  @all:
    lda #'*'
    sta BUFNOM
    lda #$00
    sta BUFNOM+1

  @ZZ0002:
    jsr _ch376_set_file_name
    jsr _ch376_file_open
    ; Au retour, on peut avoir USB_INT_SUCCESS ou USB_INT_DISK_READ)

    ; $14 -> Fichier existant (USB_INT_SUCCESS) (cas 'ls fichie.ext')
    ; $1D -> Lecture OK (USB_INT_DISk_READ
    ; $41 -> Fin de liste (ERR_OPEN_DIR) ou ouverture répertoire (cas 'ls repertoire')
    ; $42 -> fichier inexistant (ERR_MISS_FILE)

    cmp #CH376_ERR_MISS_FILE
    beq Error

    ; Ajuste le pointeur vers BUFNOM pour plus tard
    ; (le 1er caractère contient la couleur)
    inc TR2
    bne *+4
    inc TR3

  @ZZ1001:
    cmp #CH376_USB_INT_SUCCESS
    bne @ZZ1002
    lda #COLOR_FOR_FILES
    bne display_one_file_catalog

  @ZZ1002:
    cmp #CH376_ERR_OPEN_DIR
    bne @ZZ0003
    lda #COLOR_FOR_DIRECTORY
    bne display_one_file_catalog

  @ZZ0003:
    cmp #CH376_USB_INT_DISK_READ
    bne @ZZ0004

    lda #CH376_RD_USB_DATA0
    sta CH376_COMMAND
    lda CH376_DATA
    cmp #$20
    beq @ZZ0005

    ;FREE RESB
    rts

  @ZZ0005:
    jsr display_catalog

    ; display_one_file_catalog renvoie la valeur de _ch376_wait_response qui renvoie 1 en cas d'erreur
    ; et le CH376 ne renvoie pas de valeur 0
    ; donc le bne devient un saut inconditionnel!
    ; jmp @ZZ0003
    bne @ZZ0003

  @ZZ0004:
    ;FREE RESB

    BRK_ORIX XCRLF

  @ZZ0001:
    rts

; ------------------------------------------------------------------------------
Error:
    PRINT txt_file_not_found
    .BYTE $2C

display_one_file_catalog:
    .BYTE $00, XWR0

    ;FREE RESB

    PRINT BUFNOM
    BRK_ORIX XCRLF
    rts

; ------------------------------------------------------------------------------

display_catalog:
    lda #COLOR_FOR_FILES
    sta BUFNOM
    ldy #$01

  @ZZ0007:
    lda CH376_DATA
    sta BUFNOM,y
    iny
    cpy #12
    bne @ZZ0007

    lda CH376_DATA
    sta TR0         ; Sauvegarde l'attribut pour plus tard
;    cmp #$10
;    bne @ZZ0012

    and #$10
    beq @ZZ0012

    lda #COLOR_FOR_DIRECTORY
;    clc
;    adc #$40
    sta BUFNOM

  @ZZ0012:
    lda #$00
    sta BUFNOM,Y
    ;sty TEMP_ORIX_1

    ldx #$14

  @ZZ0013:
    lda CH376_DATA
    sta BUFEDT+1,y
    iny
    dex
    bpl @ZZ0013

    jsr Match
    bne @ZZ0014

    lda BUFNOM
    cmp #'.'
    beq @ZZ0014

    lda BUFNOM+1
    cmp #'.'
    beq @ZZ0015

.ifndef LS_VERBOSE
    dec NUMBER_OF_COLUMNS
    bne @ZZ0016

    ; Attention XCRLF modifie RES
; [HCL]
; Pas de saut de ligne, on est déjà au dernier caractère
; (UNIQUEMENT POUR LA VERSION LONGUE AVEC AFFICHAGE DE L'ATTRIBUT)
    BRK_ORIX XCRLF

    lda #NUMBER_OF_COLUMNS_LS
    sta NUMBER_OF_COLUMNS

  @ZZ0016:

.else
    ; Affiche l'attribut
    lda TR0
    jsr Hex2Dec
.endif

    ; PRINT BUFNOM
;    ldy #$ff
    ldy #$00
    ldx #$00

    ; Affiche directement la couleur
    ; Ne doit pas être 0
    lda BUFNOM,y
    bne  @skip

  @loop:
    iny
    lda BUFNOM,y
    beq @end

    cmp #' '
    beq @loop

    cpy #$09
    bne @suite

    pha
    CPUTC '.'
    pla
    inx

  @suite:
    ; jsr _lowercase_char
    cmp     #'A'
    bcc     @skip
    cmp     #'Z'+1
    bcs     @skip
    adc     #'a'-'A'

  @skip:
    BRK_TELEMON XWR0
    inx
    bne @loop
  @end:

    ;ldy TEMP_ORIX_1

  @ZZ0017:
    cpx #13
    beq @ZZ0018

    inx
    CPUTC ' '
    jmp @ZZ0017

  @ZZ0018:
.ifdef LS_VERBOSE
    ; Sauvegarde RES-RESB
    ; Sauvegarde TR2-TR3 (pour Match)
;    lda RES
;    pha
;    lda RES+1
;    pha
    lda RESB
    pha
    lda RESB+1
    pha
    lda TR2
    pha
    lda TR3
    pha
    jsr DisplaySize
    pla
    sta TR3
    pla
    sta TR2
    pla
    sta RESB+1
    pla
    sta RESB
;    pla
;    sta RES+1
;    pla
;    sta RES

    jsr Date
.endif

  @ZZ0015:
  @ZZ0014:

    lda #CH376_FILE_ENUM_GO
    sta CH376_COMMAND
    jsr _ch376_wait_response
    rts

optstring:
.BYT 'l',0

.endproc

; ==============================================================================
;
; Entrée:
;    RES: Pointeur vers la chaîne
;    RESB: Pointeur vers la chaîne résultat
;
; Sortie:
;    Z = 1 -> OK , C=1 -> '?' ou '*' utilisés dans le masque, (C=0 & Y=$FF -> pas de '?' ni de '*')
;    Z = 0 -> Nok, ACC=Erreur, Y=Offset dans RES, X=Offset dans RESB
;
; Utilise:
;    TR0, TR1
;
; Prepare le buffer: "????????.???"
;
.proc WildCard
    lda #'?'
    ldy #$0B-1

  @loop:
    sta (RESB),y
    dey
    bpl @loop

; Pas de '.' renvoyé par le CH376
;    lda #'.'
;    ldy #$08
;    sta (RESB),y

    lda #$00
    ldy #$0C-1
    sta (RESB),y

    ldx #$00
    ldy #$00

  Suivant:
    lda (RES),y
    beq ExtensionFill

    cmp #'.'
    beq Extension

;    cpx #$07
    cpx #$08
    beq Erreur3

    cmp #'?'
    beq Question

    cmp #'*'
    beq Star

    cmp #'0'
    bcc Erreur
    cmp #'9'+1
    bcc Ok

; Pour forcer le masque en majuscules
    cmp #'A'
    bcc Erreur
    cmp #'Z'+1
    bcc Ok

    cmp #'a'
    bcc Erreur
    cmp #'z'+1
    bcs Erreur
    and #$DF
    bne Ok

; Pour forcer le masque en minuscules
;    cmp #'z'+1
;    bcs Erreur
;    cmp #'a'
;    bcs Ok
;
;    cmp #'A'
;    bcc Erreur
;    cmp #'Z'+1
;    bcs Erreur
;    ora #$20
;    bne Ok

; Ajoute le caractère au tampon
Ok:
    sta TR0
    sty TR1
    txa
    tay
    lda TR0
    sta (RESB),y
    ldy TR1

; Incrémente les index
; Ajouter test X=09 -> erreur3?
Question:
    inx
    iny
    bne Suivant
    beq Erreur2

ExtensionFill:
    ;Cas de la chaîne vide
    cpx #$00
    beq ExtensionFin

    ; Complète l'extension avec des ' '
    txa
    tay
    lda #' '
  @loop:
    cpy #$0c-1
    beq ExtensionFin
    sta (RESB),y
    iny
    bne @loop

ExtensionFin:
    ; Place le '.' de séparation
    ;lda #'.'
    ;ldy #$08
    ;sta (RESB),y

    ;Cherche si on a utilisé des wildcards
    ldy #$0B-1
    lda #'?'
  @loop:
    cmp (RESB),Y
    beq @fin
    dey
    bpl @loop
    ; On peut supprimer le clc
    ; dans ce cas, il faudra tester Y=$FF ou Y+1=0 pour savoir
    ; si il y a des caractères '?'
    clc

  @fin:
    lda #$00
    ;tay

    rts

Erreur4:
    ; Extension trop longue
    lda #$04
    .byte $2c

Erreur3:
    ;Nom trop long
    lda #$03
    .byte $2c

Erreur2:
    ; Chaine RES trop longue
    lda #$02
    .byte $2c

Erreur:
    ; Caractère incorrect
    lda #$01

    ; ldy #$00

    ;sec
    rts

Star:
    ldx #$0c-1
  @loop:
    iny
    beq Erreur2
    lda (RES),y
    beq ExtensionFill

    cmp #'.'
    bne @loop
    ldx #$08-1
    bne ExtensionQuestion

Extension:
    cpx #$08
    beq ExtensionQuestion

    sty TR1
    txa
    tay

    lda #' '
  @loop:
    sta (RESB),y
    iny
    cpy #$08
    bne @loop

    ldy TR1
    ldx #$08-1

ExtensionQuestion:
    inx
    iny
    beq Erreur2

    lda (RES),y
    beq ExtensionFill

    cpx #$0C-1
    beq Erreur4

    cmp #'?'
    beq ExtensionQuestion

    cmp #'*'
    beq ExtensionFin

    cmp #'0'
    bcc Erreur
    cmp #'9'+1
    bcc ExtensionOk

; Pour forcer le masque en majuscules
    cmp #'A'
    bcc Erreur
    cmp #'Z'+1
    bcc ExtensionOk

    cmp #'a'
    bcc Erreur
    cmp #'z'+1
    bcs Erreur
    and #$DF
    ;bne Ok

ExtensionOk:
    sta TR0
    sty TR1
    txa
    tay
    lda TR0
    sta (RESB),y
    ldy TR1
    bne ExtensionQuestion

.endproc

;
; Entrée:
;    TR2 : Chaine
;    RESB: Masque
;
; Sortie:
;    Z = 1 -> Ok
;    Y: Offset du dernier caractère testé
;    A: Dernier caractère testé (0 si fin du masque atteinte)
;
; Note: ne vérifie pas si la longueur de la chaîne est > à celle du masque
;       - RES ne peut être utilisé à la place de TR2 (le XCRLF modifie RES)
;
.proc Match
    ldy #$ff

  @loop:
    iny

    ; Fin du masque?
    lda (RESB),y
    beq @fin

    ; Caractères identiques?
    cmp (TR2),y
    beq @loop

    ; Note: ls z?? affiche un fichier 'zx' si il existe
    cmp #'?'
    beq @loop

    ; Si on veut vérifier que la chaîne fait la même longueur que le masque
    ; (pas valable ici, les noms de fichiers sont complétés avec des ' ')
    ; rts

  @fin:
    ; Si on veut vérifier que la chaîne fait la même longueur que le masque
    ; (pas valable ici, les noms de fichiers sont complétés avec des ' ')
    ; lda (RES),y

    rts
.endproc

; ==============================================================================
; Affichage Date & Heure
;
; Buffer:
;    Date: 15-9 -> Year
;           8-5 -> Month
;           0-4 -> Day
;
;    Heure: 15-11 -> Hour
;           10- 5 -> Min
;            4- 0 -> Sec
;
; Utilise:
;    TR0-TR1 (directement)
;    TR4-TR6 (indirectement, via Bin2BCD)
;
Date:
;   CPUTC ' '
    CPUTC ' '
;    ; Encre blanche
;    lda #$87
;    BRK_ORIX XWR0


    lda #$bc
    sta TR0
    lda #$07
    sta TR1

    ldy #$0c
    lda BUFEDT+14,y
    lsr
    php

    clc
    adc TR0
    ; sta TR0
    bcc *+4
    inc TR1
    ldx #$10
    jsr Bin2BCD

    CPUTC '-'

;    lda #$00
;    sta TR1

;    ldy #$0c
    lda BUFEDT+13,y
    plp
    ror
    lsr
    lsr
    lsr
    lsr

    jsr Bin2BCD

    CPUTC '-'

;    ldy #$0c
    lda BUFEDT+13,y
    and #$1f
    jsr Bin2BCD

    CPUTC ' '
    CPUTC ' '

    lda BUFEDT+12,y
    lsr
    lsr
    lsr
    jsr Bin2BCD

    CPUTC ':'
    lda BUFEDT+12,y
    and #$07
    sta TR1
    lda BUFEDT+11,y
    and #$e0
    clc
    ror TR1
    ror
    ror TR1
    ror
    ror TR1
    ror
    ror
    ror

; Nécessaire uniquement pour afficher les secondes
;    jsr Bin2BCD
;
;    CPUTC ':'
;    lda BUFEDT+12,y
;    and #$1f
;    asl

Bin2BCD:
    ; Entrée:
    ;    TR0-TR1: Valeur binaire
    ;
    ; Sortie:
    ;    TR0-TR1: $0000
    ;    TR4-TR6: Valeur en BCD
    ;      X: $00
    ;      Y: Inchangé
    ;      A: Modifié
    sta TR0
    lda #$00
    sta TR4
    sta TR5
    sta TR6

    ldx #$10
    sed
  @loop:
    asl TR0
    rol TR0+1

    lda TR4
    adc TR4
    sta TR4

    lda TR4+1
    adc TR4+1
    sta TR4+1

    lda TR4+2
    adc TR4+2
    sta TR4+2

    dex
    bne @loop
    cld

    lda TR6
    beq *+5
    jsr Hex2Dec
    lda TR5
    beq *+5
    jsr Hex2Dec
    lda TR4

Hex2Dec:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr Hex2Asc
    pla
    and #$0f
Hex2Asc:
    ora #$30
    cmp #$3a
    bcc *+4
    adc #$05
    BRK_TELEMON XWR0
    rts


; ====================================

.ifndef print
.macro print str, option
	;
	; Call XWSTR0 function
	;
	; usage:
	;	PRINT #byte [,TELEMON|NOSAVE]
	;	PRINT (pointer) [,TELEMON|NOSAVE]
	;	PRINT address [,TELEMON|NOSAVE]
	;
	; Option:
	;	- TELEMON: when used within TELEMON bank
	;	- NOSAVE : does not preserve A,X,Y registers
	;
	.if (.not .blank({option})) .and (.not .xmatch({option}, NOSAVE)) .and (.not .xmatch({option}, TELEMON) )
		.error .sprintf("Unknown option: '%s' (not in [NOSAVE,TELEMON])", .string(option))
	.endif

	.if (.not .blank({option})) .and .xmatch({option}, NOSAVE)
		.out "Don't save regs values"
	.endif

	.if .blank({option})
		pha
		txa
		pha
		tya
		pha
	.endif

	.if (.not .blank({option})) .and .xmatch({option}, TELEMON)
		pha
		txa
		pha
		tya
		pha

		lda RES
		pha
		lda RES+1
		pha
	.endif


	.if (.match (.left (1, {str}), #))
		; .out "Immediate mode"

		lda # .right (.tcount ({str})-1, {str})
		.byte $00, XWR0

	.elseif (.match(.left(1, {str}), {(}) )
		; Indirect
		.if (.match(.right(1,{str}), {)}))
			; .out"Indirect mode"

			lda .mid (1,.tcount ({str})-2, {str})
			ldy 1+(.mid (1,.tcount ({str})-2, {str}))
			.byte $00, XWSTR0

		.else
			.error "-- PRINT: Need ')'"
		.endif

	.else
		; assume absolute
		; .out "Aboslute mode"

		lda #<str
		ldy #>str
		.byte $00, XWSTR0
	.endif

	.if .blank({option})
		pla
		tay
		pla
		txa
		pla
	.endif

	.if (.not .blank({option})) .and .xmatch({option}, TELEMON)
		pla
		sta RES+1
		pla
		sta RES

		pla
		tay
		pla
		txa
		pla
	.endif

.endmacro
.endif

.proc DisplaySize
;    CPUTC ' '
    ; Encre blanche
    lda #$87
    BRK_ORIX XWR0

    ; Copie la taille du fichier en RES-RESB
    ldy #$03
 @loop:
    lda BUFEDT+17+$0C,y
    sta RES,y
    dey
    bpl @loop

    ; Conversion en BCD
    jsr convd

    ; Conversion en chaine
    lda #<(BUFEDT+17+$0C+4)
    ldy #>(BUFEDT+17+$0C+4)
    jsr bcd2str

    ; Remplace les '0' non significatifs par des ' '
    ldy #$ff
    ldx #' '
  @skip:
    iny
    cpy #$09
    beq @display
    lda (RES),y
    cmp #'0'
    bne @display
    txa
    sta (RES),y
    bne @skip

  @display:
    ; On saute les espaces du début
;    clc
;    tya
;    adc RES
;    sta RES
;    bcc *+4
;    inc RES+1

     ; La chaine fait 10 caractères
     ; Taille maximale: < 999 999
     ; donc on saute les 4 premiers caractères
    clc
    lda #$04
    adc RES
    sta RES
    bcc *+4
    inc RES+1

    print (RES)
    rts
.endproc

; ====================================
LSB  = RES
NLSB = LSB+1
NMSB = NLSB+1
MSB  = NMSB+1
;
; Entrée:
;    RES-RESB: Valeur binaire
;
; Sortie:
;    TR0-TR4: Valeur en BCD
;
.proc convd
        ldx #$04          ; Clear BCD accumulator
        lda #$00

    BRM:
        sta TR0,x        ; Zeros into BCD accumulator
        dex
        bpl BRM

        sed               ; Decimal mode for add.

        ldy #$20          ; Y has number of bits to be converted

    BRN:
        asl LSB           ; Rotate binary number into carry
        rol NLSB
        rol NMSB
        rol MSB

;-------
; Pour MSB en premier dans BCDA
;    ldx #$05
;
;BRO:
;    lda BCDA-1,X
;    adc BCDA-1,X
;    sta BCDA-1,x
;    dex
;    bne BRO

; Pour LSB en premier dans BCDA

BCDA = (TR0-$FB) & $ff ; = $0C

        ldx #$fb          ; X will control a five byte addition.

    BRO:
        lda BCDA,x    ; Get least-signficant byte of the BCD accumulator
        adc BCDA,x    ; Add it to itself, then store.
        sta BCDA,x
        inx               ; Repeat until five byte have been added
        bne BRO

        dey               ; et another bit rom the binary number.
        bne BRN

        cld               ; Back to binary mode.
        rts               ; And back to the program.
.endproc

;
; Entrée:
;    RES: Adresse de la chaine
;    TR0-TR4: Valeur en BCD
;
.proc bcd2str
	sta RES
	sty RES+1

	ldx #$04          ; Nombre d'octets à convertir
	ldy #$00
	clc

@loop:
	; BCDA: LSB en premier
	lda TR0,X
	pha
	; and #$f0
	lsr
	lsr
	lsr
	lsr
	adc #'0'
	sta (RES),Y

	pla
	and #$0f
	adc #'0'
	iny
	sta (RES),y

	iny
	dex
	bpl @loop

	lda #$00
	sta (RES),y
	rts

.endproc

EndOfModule:
