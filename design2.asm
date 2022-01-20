assume cs:code, ss:stack, ds:data
stack segment
    dw 64 dup(0)
stack ends
data segment
    mes db 'fail to write to floppy!', 0
data ends

code segment
; 任务程序引导部分（1个扇区512字节）
; 功能: 将任务程序的主体部分读入内存
; 第一个扇区由BIOS读入内存0:7c00h处
boot:
; 从第二个扇区开始读取到0:7e00h处
; 然后跳转到任务程序主体部分task
        mov ax, 0
        mov es, ax
        mov bx, 7e00h           ; es:bx 指向接收从扇区读取数据的内存区
        
        mov al, 4	            ; 读取的扇区数
        mov ch, 0	            ; 磁道号(0~79)
        mov cl, 2	            ; 扇区号(1~18)，第二个扇区开始
        mov dl, 0	            ; 驱动器号	软驱从0开始，0:软驱A，1:软驱B
                                ; 硬盘从80h开始，80h：硬盘C，81h：硬盘D
        mov dh, 0	            ; 磁头号(0~1)（对于软盘即面号）
        mov ah, 2	            ; 功能号，2表示读扇区，3表示写扇区
        int 13h
        ; 这里失败的话，回退到从硬盘启动

        jmp bx                  ; 跳转到任务程序主体部分task

        db 512-($-boot) dup(0)  ; pad到512字节

; 任务程序主体部分（3个扇区1536字节）
; 功能：处理用户输入，执行对应操作
; 程序位于内存0:7e00h处
task:
;主程序逻辑：
;- 首先注册主菜单int9中断例程
;- 显示菜单 
;- 无限循环, 根据模式标志决定是否显示时间
        mov ax, 0               ; 9000h
        mov ds, ax              ; 主程序中将ds设为0

        call mount9             ; 注册包装过的int9中断例程

        mov cx, 5               ; 显示主菜单，5行
        mov di, 0               ;
        mov dh, 0               ; 行号
        mov dl ,0               ; 列号
s:      
        mov si, 8400h[di]       ; 菜单字符串偏移
        call showstr
        inc dh
        add di, 2               ; 指向下一个字符串的偏移
        loop s                  ;

        mov dh, 5               ; 行号
        mov dl, 0               ; 列号
        mov bx, 0               ; bh页号
        mov ah, 2               ; 功能号2: 设置光标
        int 10h

mode0:
        mov bx, offset mode-task+7e00h
        mov si, offset timeformat-task+7e00h    ; +3
        mov dh, 0
        mov dl, 0
        ; 进入无限循环
s1:
        call getclock           ; 从CMOS读取时间
        pushf
        cli                     ; 屏蔽中断，防止中断中将模式改为0后，还显示时间
        cmp byte ptr [bx], 0    ; 模式值
        je skiptime
        call showstr            ; 显示从CMOS读取的时间
skiptime:
        popf
        jmp s1

; 用于注册新的int 9中断例程，原来的中断向量保存在old9的位置
mount9:
        push ax
        push si
        mov si, offset old9-task+7e00h
        mov ax, ds:[9*4]        ; 保存原来的中断例程的偏移地址
        mov [si], ax            ; 保存到old9位置
        mov ax, ds:[9*4+2]      ; 保存原来的中断例程的段地址
        mov [si].2, ax          ; 保存到old9+2位置

        pushf
        cli                     ; 屏蔽中断，防止中断向量出现非法状态
        mov ds:[9*4], offset int9 + 7c00h   ; 设置新的int9偏移, +7c00h修正
        mov word ptr ds:[9*4+2], 0h     ; 新的int9段地址, 9000h
        popf

        pop si
        pop ax
        ret

; 恢复int 9中断例程为BIOS自带的那个
umount9:
        push ax
        push si
        mov si, offset old9-task+7e00h
        pushf
        cli                     ; 屏蔽中断，防止中断向量出现非法状态
        mov ax, [si]
        mov ds:[9*4], ax        ; 偏移地址
        mov ax, [si].2
        mov ds:[9*4+2], ax      ; 段地址
        popf

        pop si
        pop ax
        ret

;主选菜单int9中断例程逻辑：（处理字符1~4）
;- 用户输入1，重新启动计算机，跳到ffff:0执行
;- 用户输入2，首先复原int9中断例程，然后清屏，将硬盘第一个扇区内容读到0:7c00，跳转到0:7c00
;- 用户输入3，保存屏幕(主选单)，清屏，修改模式为1(动态显示时间)
;- 用户输入4，首先复原int9中断例程，保存屏幕(主选单)，清屏，显示提示字符串
;             等待用户输入日期时间，检查格式是否正确，将时间设置到CMOS RTC上
;             完成之后恢复屏幕，重新安装我们包装的int 9中断例程。
;
;时钟程序int9中断例程逻辑：（处理F1和Esc）
;- 用户输入F1，改变显示颜色
;- 用户输入Esc，恢复屏幕，修改模式为0（主选单）
subf1:
        mov ah, 1               ; 功能号1, 修改颜色
        call screen
        jmp int9ret
subesc:
        ; 恢复屏幕
        mov ah, 3               ; 功能号3, 恢复
        call screen

        mov byte ptr [bx], 0    ; 模式改为0

        push dx
        mov dh, 5               ; 行号
        mov dl, 0               ; 列号
        mov bx, 0               ; bx已经不用了, 可以覆盖
        mov ah, 2               ; 功能号2: 设置光标
        int 10h
        pop dx

        jmp int9ret

int9:
        push ax
        push bx
        push si

        pushf                   ; 中断过程：标志寄存器入栈

        mov si, offset old9-task+7e00h
        call dword ptr [si]     ; 中断过程：模拟int9

int9s:
        mov ah, 1               ; int9进来，键盘缓冲区不一定有数据
        int 16h
        je int9ret

        mov ah, 0
        int 16h                 ; 读取键盘缓冲区,防止键盘缓冲区溢出
                                ; (ah)=scan code, (al)=ascii

int9s1:
        ;in al, 60h      ; 从60h端口读取扫描码

        mov bx, offset mode-task+7e00h
        mov al, [bx]            ; 获取模式值
        cmp al, 1
        je timemode
        cmp ah, 02              ; 1的扫描码02
        je sub1
        cmp ah, 03              ; 2的扫描码03
        je sub2
        cmp ah, 04              ; 3的扫描码04
        je sub3
        cmp ah, 05              ; 4的扫描码05
        je sub4
        jmp int9ret
timemode:
        cmp ah, 3bh             ; F1的扫描码3bh
        je subf1
        cmp ah, 01              ; Esc的扫描码01
        je subesc
        jmp int9ret
int9ret:
        pop si
        pop bx
        pop ax
        iret

sub1:
        ; 需要清栈么
        pop si
        pop ax
        mov ax, 0ffffh
        push ax
        mov ax, 0
        push ax
        retf                    ; 0ffffh:0
sub2:
        push cx
        push dx
        push es
        call umount9            ; 调用umount9

        ; 清屏
        mov ah, 0               ; 功能号0, 清屏
        call screen

        mov dh, 0               ; 行号
        mov dl, 0               ; 列号
        mov bx, 0               ; bh页号
        mov ah, 2               ; 功能号2: 设置光标
        int 10h

; 从硬盘第一个扇区读取到0:7c00h处
; 然后跳转
        mov ax, 0
        mov es, ax
        mov bx, 7c00h           ; es:bx 指向接收从扇区读取数据的内存区
        
        mov al, 1	            ; 读取的扇区数
        mov ch, 0	            ; 磁道号
        mov cl, 1	            ; 扇区号，第一个扇区开始
        mov dl, 80h	            ; 驱动器号	软驱从0开始，0:软驱A，1:软驱B；硬盘从80h开始，80h：硬盘C，81h：硬盘D
        mov dh, 0	            ; 磁头号（对于软盘即面号）
        mov ah, 2	            ; 功能号，2表示读扇区，3表示写扇区
        int 13h

        ; 需要清栈么
        jmp bx                  ; 跳转到硬盘引导

sub3:
        ; 保存屏幕
        mov ah, 2               ; 功能号2, 保存
        call screen

        ; 清屏
        mov ah, 0               ; 功能号0, 清屏
        call screen

        mov byte ptr [bx], 1    ; 模式改为1

        push dx
        mov dh, 0               ; 行号
        mov dl, 17              ; 列号
        mov bx, 0               ; bx已经不用了, 可以覆盖
        mov ah, 2               ; 功能号2: 设置光标
        int 10h
        pop dx

        jmp int9ret

;处理用户输入的时间:
; 调用int 16h读取键盘缓冲区
; 使用一个字符栈来保存用户输入的字符，同时用一个变量top保存当前栈顶的位置。
; 
; - 当用户输入字符时：首先检查是否到栈顶， 到了栈顶则忽略，否则将字符入栈，然后更新屏幕显示
; - 当用户输入退格键时：如果栈是空的，不做啥操作，否则弹出一个字符，然后更新屏幕显示
; - 当用户输入Enter键时：结束输入过程

sub4:
        push dx
        call umount9            ; 恢复原来的int 9中断例程

        mov ah, 2               ; 功能号2, 保存屏幕
        call screen

sub4s:
        mov ah, 0               ; 功能号0, 清屏
        call screen

        mov si, offset prompt-task+7e00h
        mov dh, 0
        mov dl, 0
        call showstr            ; 显示提示字符串

        mov dh, 1               ; 行号
        mov bx, 0               ; bx已经不用了, 可以覆盖
        mov ah, 2               ; 功能号2: 设置光标
        int 10h

        mov si, offset charstk-task+7e00h
        call inputclock         ; 用户输入字符串
        call checkclock         ; 检查字符串格式是否合法
        cmp ah, 0
        jne sub4s               ; 格式不正确，重新输入 

        call setclock           ; 写到CMOS RTC

        mov ah, 3               ; 功能号3, 恢复屏幕
        call screen             ; call screen

        mov dh, 5               ; 行号
        mov dl, 0               ; 列号
        mov bx, 0               ; bx已经不用了, 可以覆盖
        mov ah, 2               ; 功能号2: 设置光标
        int 10h

        call mount9             ; 重新注册新的int9中断例程

        pop dx
        jmp int9ret

; 屏幕相关操作
; ah 功能号: 0清屏, 1换颜色, 2保存当前屏幕，3恢复保存的屏幕
; 从第0页保存到第1页，从第1页恢复到第0页
screen:
        push ax
        push bx
        push cx
        push ds
        push es
        push si
        push di

        cmp ah, 0
        je clear
        cmp ah, 1
        je color
        cmp ah, 2
        je save
        cmp ah, 3
        je restore
        jmp screenret

clear:
        mov ax, 0b800h                  ; 显示缓冲区第0页起始地址
        mov ds, ax
        mov si, 0
        mov cx, 2000                    ; 80 * 25
clears:
        mov byte ptr [si], ' '          ; 清屏
        mov byte ptr [si].1, 00000111b  ; 黑底白字
        add si, 2
        loop clears
        jmp screenret

color:
        mov ax, 0b800h                  ; 显示缓冲区第0页起始地址
        mov ds, ax
        mov si, 1
        mov cx, 2000                    ; 80 * 25
colors:
        inc byte ptr [si]               ; 修改颜色
        add si, 2
        loop colors
        jmp screenret

save:
        mov ax, 0b800h                  ; 第0页起始地址
        mov ds, ax
        mov si, 0
        mov ax, 0b8fah                  ; 第1页起始地址 
        mov es, ax
        mov di, 0
        mov cx, 4000                    ; 80 * 25 * 2
        cld                             ; df=0
        rep movsb
        jmp screenret

restore:
        mov ax, 0b8fah                  ; 第1页起始地址 
        mov ds, ax
        mov si, 0
        mov ax, 0b800h                  ; 第0页起始地址
        mov es, ax
        mov di, 0
        mov cx, 4000
        cld                             ; df=0
        rep movsb

screenret:
        pop di
        pop si
        pop es
        pop ds
        pop cx
        pop bx
        pop ax
        ret

; 在屏幕指定位置显示以0结尾的字符串
; 参数: (dh)=行号，(dl)=列号，ds:si指向字符串首地址

showstr:
        push ax
        push cx
        push es
        push di
        push si
        mov ax, 0b800h
        mov es, ax
        mov ax, 160             ; 根据行列计算起始位置
        mul dh
        mov di, ax
        mov ax, 2
        mul dl
        add di, ax

        mov cx, 0
showstrs:
        mov cl, [si]
        jcxz showstrok
        mov es:[di], cl         ; 字符
        add di, 2
        inc si
        jmp short showstrs

showstrok:
        pop si
        pop di
        pop es
        pop cx
        pop ax
        ret

; 在屏幕指定位置以十六进制显示内存数据
; 参数: (dh)=行号, (dl)=列号，ds:si指向内存起始地址
;       (cx)=要打印的长度
hexdump:
        push ax
        push bx
        push cx
        push es
        push di
        push si
        push bp
        mov bx, offset hextable-task+7e00h
        mov ax, 0b800h
        mov es, ax
        mov ax, 160
        mul dh
        mov bp, ax
        mov ax, 2
        mul dl
        add bp, ax
        jcxz hexdumpok 
hexdumps:
        push cx
        mov ax, 0
        mov al, [si]
        mov cl, 4
        shr al, cl
        mov di, ax              ; 高4位
        mov ah, [bx+di]
        mov es:[bp], ah

        mov ax, 0
        mov al, [si]
        and al, 00001111b
        mov di, ax              ; 低4位
        mov ah, [bx+di]
        mov es:[bp].2, ah
        add bp, 4
        inc si
        pop cx
        loop hexdumps

hexdumpok:
        pop bp
        pop si
        pop di
        pop es
        pop cx
        pop bx
        pop ax
        ret

; 字符栈的入栈、出栈和显示
; 参数说明: (ah)=功能号，0入栈，1出栈，2显示
;           ds:si 指向字符栈空间
;           对于0号功能: (al)=入栈字符
;           对于1号功能: (al)=返回的字符
;           对于2号功能: (dh)和(dl)=字符串在屏幕上显示的行、列
charstack:
        push bx
        push di
        push es
        push bp
        mov bp, offset top-task+7e00h
        cmp ah, 0
        je charpush
        cmp ah, 1
        je charpop
        cmp ah, 2
        je charshow
        jmp charret

charpush:
;        cmp word ptr ds:[bp], 0
;        je charpush
;        mov word ptr ds:[bp], 0

;        push dx
;        push si
;        push cx
;        mov cx, 2
;        mov dh, 10
;        mov dl, 10
;        mov si, bp
;        call hexdump
;        pop cx
;        pop si
;        pop dx


        mov bx, ds:[bp]         ; top的值
        cmp bx, 31              ; 防止溢出
        ja charret
        mov [si][bx], al
        inc word ptr ds:[bp]
        jmp charret
charpop:
        cmp word ptr ds:[bp], 0
        je charret
        dec word ptr ds:[bp]
        mov bx, ds:[bp]
        mov al, [si][bx]
        jmp charret
charshow:
        mov bx, 0b800h
        mov es, bx
        mov ax, 160
        mul dh                  ; 行号*160
        mov di, ax
        mov ax, 2
        mul dl                  ; 列号*2
        add di, ax

        mov bx, 0
charshows:
        cmp bx, ds:[bp]
        jne noempty
        mov byte ptr es:[di], ' '

        push dx
        mov dl, bl
        mov bx, 0               ; bx已经不用了, 可以覆盖
        mov ah, 2               ; 功能号2: 设置光标
        int 10h
        pop dx
        jmp charret
noempty:
        mov al, [si][bx]
        mov es:[di], al
        mov byte ptr es:[di+2], ' '
        inc bx
        add di, 2
        jmp charshows

charret:
        pop bp
        pop es
        pop di
        pop bx
        ret

; 输入时间，从键盘缓冲区读取
; dh, dl 显示的行号列号
; ds:si 指向字符栈起始位置
inputclock:
        push ax
        push bx
        push si
        mov bx, offset top-task+7e00h
        mov word ptr [bx], 0    ; top先清0

        ; 先清空键盘缓冲区
cleanbuf:
        mov ah, 1
        int 16h
        je getstrs
        mov ah, 0
        int 16h
        jmp cleanbuf

getstrs:
        mov ah, 0
        int 16h
        cmp al, 20h             ; ASCII码小于20h，说明不是字符
        jb nochar
        mov ah, 0
        call charstack          ; 字符入栈
        mov ah, 2
        call charstack          ; 显示栈中的字符
        jmp getstrs
nochar:
        cmp ah, 0eh             ; 退格键的扫描码
        je backspace
        cmp ah, 1ch             ; Enter键的扫描码
        je enter
        jmp getstrs
backspace:
        mov ah, 1
        call charstack          ; 字符出栈
        mov ah, 2
        call charstack          ; 显示栈中的字符
        jmp getstrs
enter:
        pop si
        pop bx
        pop ax
        ret

; 检查时间格式是否正确
; 参数: ds:si指向字符栈起始位置
; 返回: (ah)=0表示格式正确, (ah)=1表示格式错误 
; yy/MM/dd hh:mm:ss
checkclock:
        push bx
        push cx
        push dx
        push si
        push di
        push ax

        ; 检查数字
        mov di, offset digitoffset-task+7e00h
        mov bx, 0
        mov cx, 12

checkdigits:
        mov bl, [di]            ; 获取数字在字符串中的偏移量
        mov al, [si][bx]
        call isdigit            ; 检查对应位置是否是数字
        cmp ah, 0
        jne checkfail           ; 返回值0表示是数字
        inc di
        loop checkdigits

        ; 检查特殊符号
        mov cx, 5
        mov di, offset timeformat-task+7e00h
        mov bx, 2               ; +3
checksigns:
        mov al, [di][bx]
        cmp [si][bx], al        ; 检查对应位置的符号是否正确
        jne checkfail
        add bx, 3
        loop checksigns

        ; 检查日期
        call checkdate          ; 检查日期是否合法，包括闰年的检查
        cmp ah, 0
        jne checkfail

        ; 检查时间
        add si, 9
        call checktime          ; 检查时间是否合法
        cmp ah, 0
        jne checkfail

        pop ax
        mov ah, 0
        jmp checkend
checkfail:
        pop ax
        mov ah, 1
checkend:
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        ret

; 检查字符是否是数字
; 参数: (al)为要检查的字符
; 返回: (ah)=0表示是数字, (ah)=1表示不是数字
isdigit:
        cmp al, '0'
        jb notdigit
        cmp al, '9'
        ja notdigit
        mov ah, 0
        ret

notdigit:
        mov ah, 1
        ret


; 检查日期是否合法
; 参数: ds:si指向字符串起始位置
; 返回: (ah)=0表示格式正确, (ah)=1表示格式错误 
; YY/MM/dd
checkdate:
        push bx
        push si
        push di
        push ax

        ; 检查月份是否超出
        add si, 3               ; 月份从位置3开始
        call char2number        ; 将ds:si所指位置的两个字符转成数值
        cmp al, 1               ; 月份有效值1到12
        jb datefail
        cmp al, 12
        ja datefail

        mov bx, 0
        mov bl, al              ; 月份先保存到bl

        ; 检查日期是否超出
        add si, 3               ; 日期从位置6开始
        call char2number
        cmp al, 1               ; 日期最小1
        jb datefail

        mov di, offset daysofmonth-task+7e00h
        cmp al, [di][bx]
        ja datefail             ; 最大根据月份来判断

        ; 不是2月29日不用检查闰年
        cmp al, 29
        jne datepass
        cmp bl, 2
        jne datepass

        ; 检查闰年
        mov bh, al              ; 日期先保存到bl
        mov ax, 0
        sub si, 6
        call char2number
        add ax, 1900            ; (al)>=90, 认为是19YY 
        cmp ax, 1990
        jnb nineteenth 
        add ax, 100             ; (al)<90, 认为是20YY
nineteenth:
        call isleapyear         ; 判断ax所表示的年份是否是闰年
        cmp ah, 0
        jne datepass            ; 闰年不能有2月29日
datefail:
        pop ax
        mov ah, 1
        jmp dateend
datepass:
        pop ax
        mov ah, 0
dateend:
        pop di
        pop si
        pop dx
        ret

; 检查时间是否合法
; 参数: ds:si指向字符串起始位置
; 返回: (ah)=0表示格式正确, (ah)=1表示格式错误 
; hh:mm:ss
checktime:
        push si
        push ax

        ; 检查小时
        call char2number        ; 转成数值
        cmp al, 23
        ja timefail

        ; 检查分钟
        add si, 3
        call char2number
        cmp al, 59
        ja timefail

        ; 检查秒钟
        add si, 3
        call char2number
        cmp al, 59
        ja timefail

        pop ax
        mov ah, 0
        jmp timeend
timefail:
        pop ax
        mov ah, 1
timeend:
        pop si
        ret


; 检查指定年份是否是闰年
; 参数: (ax)=年份，四位数YYYY
; 返回值: (ah)=0表示闰年，(ah)=1不是闰年
isleapyear:
        push cx
        push dx
        mov dx, ax              ; 暂时保存年份
        mov cx, 4
        call divdb              ; 不会溢出的除法, 除数为字节型
        cmp cl, 0
        jne notleap             ; 不能被4整除，不是闰年

        mov ax, dx              ; 年份
        mov cx, 100
        call divdb
        cmp cl, 0
        jne leapyear            ; 能被4整除，不能被100整除，是闰年
        
        mov ax, dx
        mov dx, 0
        mov cx, 400
        div cx                  ; 不可能溢出，直接用div
        cmp dx, 0
        jne notleap             ; 能被100整除，不能被400整除的，不是闰年
leapyear:
        mov ah, 0
        jmp leapend
notleap:
        mov ah, 1
leapend:
        pop dx
        pop cx
        ret

; 设置CMOS RTC时间
; 参数: ds:si指向字符串起始位置
; 实际测试，不是闰年也设置不了2月29日
; 2月28日直接跳到3月1日, 暂不清楚原因
setclock:
        push ax
        push cx
        push si
        push di

        mov di, offset timeoffset-task+7e00h
        mov cx, 6               ; 循环次数
setclocks:
        mov al, [di]            ; 获取内存单元号
        out 70h, al             ; 写到控制端口

        mov ah, [si]            ; 十位字符
        sub ah, 30h             ; 实际数值
        push cx
        mov cl, 4               ; 左移位数
        shl ah, cl              ; 高4位放十位的值
        pop cx
        mov al, [si].1          ; 个位字符
        sub al, 30h             ; 实际数值
        add al, ah              ; 相加

        out 71h, al             ; 写到数据端口

        add si, 3
        inc di
        loop setclocks

        pop di
        pop si
        pop cx
        pop ax
        ret

; 设置CMOS RTC时间
; 参数: ds:si指向字符串起始位置
getclock:
        push ax
        push cx
        push si
        push di

        mov di, offset timeoffset-task+7e00h
        mov cx, 6               ; 循环次数
getclocks:
        mov al, [di]            ; 获取内存单元号
        out 70h, al             ; 写到控制端口
        in al, 71h              ; 从数据端口读取

        mov ah, al
        push cx
        mov cl, 4               ; 右移位数
        shr ah, cl              ; ah中为十位
        pop cx
        and al, 00001111b       ; al中为个位
        add ah, 30h             ; 对应ascii码
        add al, 30h             ; 对应ascii码
        mov [si], ah
        mov [si].1, al

        add si, 3
        inc di
        loop getclocks

        pop di
        pop si
        pop cx
        pop ax
        ret

; 将两个字符表示的数字转成字节型数据
; 参数: ds:si指向字符起始位置
; 返回: (al)=转化后的字节型数据
char2number:
        push bx
        push ax
        mov ax, 0
        mov bl, [si]            ; 获取十位字符
        sub bl, 30h             ; -30h 转成实际数值
        mov al, 10              ; 十位 * 10
        mul bl
        mov bl, [si].1          ; 获取个位字符
        sub bl, 30h             ; -30h 转成实际数值
        add bl, al              ; 相加得到结果

        pop ax                  ; 这里是为了不影响ah的值
        mov al, bl
        pop bx
        ret

; 名称 divdb
; 功能 进行不会产生溢出的除法运算，被除数为word，除数为byte，结果为word
; 参数 (ax)=word型数据
;      (cl)=除数
; 返回 (ax)=商
;      (cl)=余数
; 扩展为dword除word, 商不可能溢出
divdb:
        push dx
        push cx
        mov dx, 0               ; 高位补0
        mov ch, 0               ; 高位补0
        div cx

        pop cx                  ; 这里为了不影响ch
        mov cl, dl              ; 余数
        pop dx
        ret

; 名称 divdw
; 功能 进行不会产生溢出的除法运算，被除数为dword，除数为word，结果为dword
; 参数 (ax)=dword型数据的低16位
;      (dx)=dword型数据的高16位
;      (cx)=除数
; 返回 (dx)=结果的高16位，(ax)=结果的低16位
;      (cx)=余数
; 公式 X/N = int(H/N)*65536 + [rem(H/N)*65536+L]/N
divdw:  push bx
        push di

        mov bx, ax              ; 低位L先保存
        mov ax, dx              ; 高位H移到ax
        mov dx, 0
        div cx                  ; H/N

        mov di, ax              ; int(H/N)

        mov ax, bx              ; 低位L移到ax，rem(H/N)已经在dx中
        div cx                  ; [rem(H/N)*65536+L]/N

        mov cx, dx              ; 余数
        mov dx, di              ; 商高位，低位已经在ax中

        pop di
        pop bx
        ret

    db 1536-($-task) dup(0)     ; pad到3个扇区的长度

; 任务程序数据部分（1个扇区512字节）
dat:
    ; 相对task偏移+7e00h
    ; m1:0, m2:1, m3:2, m4:3, m5:4
    dw offset m1-task+7e00h, offset m2-task+7e00h, offset m3-task+7e00h
    dw offset m4-task+7e00h, offset m5-task+7e00h
    m1 db '--------------------------------------MENU--------------------------------------', 0
    m2 db '1) reset pc', 0          ; 重新启动计算机
    m3 db '2) start system', 0      ; 引导现有的操作系统
    m4 db '3) clock', 0             ; 进入时钟程序
    m5 db '4) set clock', 0         ; 设置时间
    prompt db 'time format: yy/MM/dd hh:mm:ss', 0   ; 设置时间提示字符串
    timeformat db 'yy/MM/dd hh:mm:ss', 0            ; 时间格式
    timeoffset db 9, 8, 7, 4, 2, 0                  ; CMOS时间各项寄存器号
    old9 dd 0                       ; 保存int9中断原本的地址 
    mode db 0                       ; int9中断例程模式，0表示主选项，1表示时间程序
    charstk db 32 dup(0)            ; 设置时间的字符栈
    top dw 0
    digitoffset db 0,1,3,4,6,7,9,10,12,13,15,16     ; 时间字符串中数字的偏移
    daysofmonth db 0,31,29,31,30,31,30,31,31,30,31,30,31     ; 每个月的天数
    hextable db '0123456789ABCDEF'  ; 十六进制打印

    db 512-($-dat) dup(0)           ; pad到512字节

; 安装程序: 将任务程序写到软盘上
start:
        mov ax, data
        mov ds, ax
        mov ax, stack
        mov ss, ax
        mov sp, 128

        mov ax, cs
        mov es, ax
        mov bx, offset boot	    ; es:bx 指向缓存数据的内存地址
        
        mov al, 5	            ; 读写的扇区数
        mov ch, 0	            ; 磁道号
        mov cl, 1	            ; 扇区号
        mov dl, 0	            ; 驱动器号	软驱从0开始，0:软驱A，1:软驱B；
                                ; 硬盘从80h开始，80h：硬盘C，81h：硬盘D
        mov dh, 0	            ; 磁头号（对于软盘即面号）
        mov ah, 3	            ; 功能号，2表示读扇区，3表示写扇区
        int 13h

        cmp ah, 0
        je ok
        mov dh, 10
        mov dl, 10
        mov si, 0
        call showstr

;;        直接把task开始的扇区拷贝到0:7e00处, 没有软驱时测试
;        mov ax, stack
;        mov ss, ax
;        mov sp, 128
;
;        mov ax, 9000h
;        mov es, ax
;        mov di, 7e00h
;
;        mov ax, cs
;        mov ds, ax
;        mov si, offset task
;
;        mov cx, offset start - offset task
;        cld                     ; df=0
;        rep movsb
;
;        mov di, 7e00h
;        push es
;        push di
;        retf
;
ok:
        mov ax, 4c00h
        int 21h

        
code ends
end start
