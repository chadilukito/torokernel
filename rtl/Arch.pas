//
// Arch.pas
//
// This unit contains the functions and procedures for a particular architecture.
// In this case, the unit is defined for x86-64.
//
// Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>
// All Rights Reserved
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

unit Arch;

{$I Toro.inc}

interface

const
  EXC_DIVBYZERO = 0;
  EXC_OVERFLOW = 4;
  EXC_BOUND = 5;
  EXC_ILLEGALINS = 6;
  EXC_DEVNOTAVA = 7;
  EXC_DF = 8;
  EXC_STACKFAULT = 12;
  EXC_GENERALP = 13;
  EXC_PAGEFAUL = 14;
  EXC_FPUE = 16;

  MEM_AVAILABLE = 1;
  MEM_RESERVED = 2;

  // Max CPU speed in Mhz
  MAX_CPU_SPEED_MHZ = 2393;

type
{$IFDEF UNICODE}
  XChar = AnsiChar;
  PXChar = PAnsiChar;
{$ELSE}
  XChar = Char;
  AnsiString = string;
  PXChar = PChar;
{$ENDIF} // Alias type XMLString for string or WideString
{$IFDEF FPC}
  UInt32 = Cardinal;
  UInt64 = QWORD;
{$ENDIF}
{$IFDEF DCC}
  DWORD = UInt32;
  PDWORD = ^DWORD;
  QWORD = UInt64;
  SizeUInt = QWORD;
  PtrInt = Int64;
  PtrUInt = UInt64;
{$ENDIF}
  TNow = record
    Sec : LongInt;
    Min: LongInt;
    Hour: LongInt;
    Day: LongInt;
    Month: LongInt;
    Year: LongInt
  end;
  PNow = ^TNow;

  TMemoryRegion = record
    Base: QWord;
    Length: QWord;
    Flag: Word; // MEM_RESERVED, MEM_AVAILABLE
  end;
  PMemoryRegion = ^TMemoryRegion;

  TCore = record
    ApicID: LongInt;
    Present: Boolean;
    CPUBoot: Boolean;
    InitConfirmation: Boolean;
    InitProc: procedure;
  end;

procedure bit_reset(Value: Pointer; Offset: QWord);
procedure bit_set(Value: Pointer; Offset: QWord); assembler;
function bit_test ( Val : Pointer ; pos : QWord ) : Boolean;
procedure change_sp (new_esp : Pointer ) ;
procedure Delay(ms: LongInt);
procedure eoi;
function GetApicID: Byte;
function GetApicBaseAddr: Pointer;
function get_irq_master: Byte;
function get_irq_slave: Byte;
procedure IrqOn(irq: Byte);
procedure IrqOff(irq: Byte);
function is_apic_ready: Boolean ;
procedure NOP;
function read_portb(port: Word): Byte;
procedure read_portd(Data: Pointer; Port: Word);
function read_rdtsc: Int64;
procedure send_apic_init (apicid : Byte) ;
procedure send_apic_startup (apicid , vector : Byte );
function SpinLock(CmpVal, NewVal: UInt64; var addval: UInt64): UInt64; assembler;
procedure SwitchStack(sv: Pointer; ld: Pointer);
procedure write_portb(Data: Byte; Port: Word);
procedure write_portd(const Data: Pointer; const Port: Word);
procedure write_portw(Data: Word; Port: Word);
procedure CaptureInt (int: Byte; Handler: Pointer);
procedure CaptureException(Exception: Byte; Handler: Pointer);
procedure ArchInit;
procedure Now (Data: PNow);
procedure Interruption_Ignore;
procedure IRQ_Ignore;
function PciReadDWORD(const bus, device, func, regnum: UInt32): UInt32;
function PciReadByte(const bus, device, func: DWORD; offset: Byte): Byte;
function GetMemoryRegion (ID: LongInt ; Buffer : PMemoryRegion): LongInt;
function InitCore(ApicID: Byte): Boolean;
procedure SetPageCache(Add: Pointer);
procedure RemovePageCache(Add: Pointer);
function SecondsBetween(const ANow: TNow;const AThen: TNow): LongInt;
procedure ShutdownInQemu;
procedure Reboot;
procedure DelayMicro(microseg: LongInt);
procedure PciWriteWord (const bus, device, func, regnum, value: Word);
function read_portw(port: Word): Word;
function PciReadWORD(const bus, device, func, regnum: UInt32): Word;
procedure SetPageReadOnly(Add: Pointer);
procedure send_apic_int (apicid, vector: Byte);
procedure eoi_apic;
procedure monitor(addr: Pointer; ext: DWORD; hint: DWORD);
procedure mwait(ext: DWORD; hint: DWORD);
procedure hlt; assembler;
procedure ReadBarrier;assembler;{$ifdef SYSTEMINLINE}inline;{$endif}
procedure ReadWriteBarrier;assembler;{$ifdef SYSTEMINLINE}inline;{$endif}
procedure WriteBarrier;assembler;{$ifdef SYSTEMINLINE}inline;{$endif}
function GetKernelParam(I: LongInt): Pchar;

const
  MP_START_ADD = $e0000;
  RESET_VECTOR = $467; // when the IPI occurs the procesor jumps here
  cpu_type = 0;
  apic_type = 2;
  MAX_CPU = 8;  // Number of max CPU support
  ALLOC_MEMORY_START = $800000; // Address Start of Alloc Memory
  KERNEL_IMAGE_START = $400000;
  PAGE_SIZE = 2*1024*1024; // 2 MB per Page
  HasCacheHandler: Boolean = True;
  HasException: Boolean = True;
  HasFloatingPointUnit : Boolean = True;
  INTER_CORE_IRQ = 80;

var
  CPU_COUNT: LongInt;
  AvailableMemory: QWord;
  LocalCpuSpeed: Int64 = 0; // LocalCpuSpeed has the speed of the local CPU in Mhz
  StartTime: TNow;
  Cores: array[0..MAX_CPU-1] of TCore;
  LargestMonitorLine: longint;
  SmallestMonitorLine: longint;
  KernelParam: Pchar = Nil;

implementation

uses Kernel, Console;

{$MACRO ON}
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}

const
  Apic_Base = $FEE00000; // $FFFFFFFF - $11FFFFF // = 18874368 -> 18MB from the top end
  apicid_reg = apic_base + $20;
  icrlo_reg = apic_base + $300;
  icrhi_reg = apic_base + $310;
  err_stat_reg = apic_base + $280;
  timer_reg = apic_base + $320;
  timer_init_reg = apic_base + $380;
  timer_curr_reg = apic_base + $390;
  divide_reg = apic_base + $3e0;
  eoi_reg = apic_base + $b0;
  svr_reg = apic_base + $f0;

  // IDT descriptors
  gate_syst = $8E;

  // Address of Page Directory
  PDADD = $100000;
  Kernel_Param = $200000;
  IDTADDRESS = $3020;

  Kernel_Code_Sel = $18;
  Kernel_Data_Sel = $10;

  size_start_stack = 700;

type
  p_apicid_register = ^apicid_register ;
  apicid_register = record
    res : Word ;
    res0 : Byte ;
    apicid : Byte ;
  end;

  TGDTR = record
    limite: Word;
    res1, res2: DWORD;
  end;

  p_mp_floating_struct  = ^mp_floating_struct ;
  mp_floating_struct = record
    signature: array[0..3] of XChar;
    phys: DWORD;
    data: DWORD;
    mp_type: DWORD;
  end;

  p_mp_table_header = ^mp_table_header ;
  mp_table_header = record
    signature : array[0..3] of XChar ;
    res: array[0..6] of DWORD ;
    size: Word ;
    count: Word ;
    addres_apic: DWORD;
    resd: DWORD ;
  end;

  p_mp_processor_entry = ^mp_processor_entry ;
  mp_processor_entry = record
    tipe: Byte ;
    apic_id: Byte ;
    apic_ver: Byte ;
    flags: Byte ;
    signature: DWORD ;
    feature: DWORD ;
    res: array[0..1] of DWORD ;
  end;

  p_mp_apic_entry = ^mp_apic_entry ;
  mp_apic_entry = record
    tipe : Byte ;
    apic_id : Byte ;
    apic_ver : Byte ;
    flags : Byte ;
    addres_apic : DWORD ;
  end;

  TInteruptGate = record
    handler_0_15: Word;
    selector: Word;
    nu: Byte;
    tipe: Byte;
    handler_16_31: Word;
    handler_32_63: DWORD;
    res: DWORD;
  end;

  TInterruptGateArray = array[0..255] of TInteruptGate;
  PInterruptGateArray = ^TInterruptGateArray;
  p_intr_gate_struct = ^TInteruptGate;

  PDirectoryPage = ^TDirectoryPageEntry;
  TDirectoryPageEntry = record
    PageDescriptor: QWORD;
  end;

var
  idt_gates: PInterruptGateArray; // Pointer to IDT
  mbpointer: Pointer;

procedure CaptureInt(int: Byte; Handler: Pointer);
begin
  Move(PtrUInt(Handler), idt_gates^[int].handler_0_15, sizeof(WORD));
  idt_gates^[int].selector := kernel_code_sel;
  idt_gates^[int].tipe := gate_syst;
  idt_gates^[int].handler_16_31 := Word((PtrUInt(Handler) shr 16) and $ffff);
  idt_gates^[int].handler_32_63 := DWORD(PtrUInt(Handler) shr 32);
  idt_gates^[int].res := 0;
  idt_gates^[int].nu := 0;
end;

procedure CaptureException(Exception: Byte; Handler: Pointer);
begin
  Move(PtrUInt(Handler), idt_gates^[Exception].handler_0_15, sizeof(WORD));
  idt_gates^[Exception].selector := kernel_code_sel;
  idt_gates^[Exception].tipe := gate_syst ;
  idt_gates^[Exception].handler_16_31 := Word((PtrUInt(Handler) shr 16) and $ffff);
  idt_gates^[Exception].handler_32_63 := DWORD(PtrUInt(Handler) shr 32);
  idt_gates^[Exception].res := 0 ;
  idt_gates^[Exception].nu := 0 ;
end;

procedure write_portb(Data: Byte; Port: Word); assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  {$IFDEF LINUX} mov dx, port {$ENDIF}
  mov al, data
  out dx, al
end;

procedure write_portw(Data: Word; Port: Word); assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  {$IFDEF LINUX} mov dx, port {$ENDIF}
  mov ax, data
  out dx, ax
end;

function read_portb(port: Word): Byte; assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov dx, port
  in al, dx
end;

function read_portw(port: Word): Word; assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov dx, port
  in ax, dx
end;

procedure write_portd(const Data: Pointer; const Port: Word); {$IFDEF ASMINLINE} inline; {$ENDIF}
asm // RCX: data, RDX: port
  push rsi
  {$IFDEF LINUX} mov dx, port {$ENDIF}
  mov rsi, data // DX=port
  outsd
  pop rsi
end;

procedure read_portd(Data: Pointer; Port: Word); {$IFDEF ASMINLINE} inline; {$ENDIF}
asm // RCX: data, RDX: port
  push rdi
  {$IFDEF LINUX} mov dx, port {$ENDIF}
  mov rdi, data // DX=port
  insd
  pop rdi
end;

procedure send_apic_init(apicid: Byte);
var
  icrl, icrh: ^DWORD;
begin
  icrl := Pointer(icrlo_reg);
  icrh := Pointer(icrhi_reg) ;
  icrh^ := apicid shl 24 ;
  icrl^ := $500 or $8000 or $4000; // INIT or LEVEL or ASSERT
  DelayMicro(200);
  icrl^ := $500 or $8000; // INIT or LEVEL
  DelayMicro(200);
end;

procedure send_apic_startup(apicid, vector: Byte);
var
  icrl, icrh: ^DWORD;
begin
  icrl := Pointer(icrlo_reg);
  icrh := Pointer(icrhi_reg) ;
  icrh^ := apicid shl 24 ;
  // mode: init, destination no shorthand
  icrl^ := $600 or vector;
end;

procedure send_apic_int (apicid, vector: Byte);
var
  icrl, icrh: ^DWORD;
begin
  Delay(10);
  icrl := Pointer(icrlo_reg);
  icrh := Pointer(icrhi_reg) ;
  icrh^ := apicid shl 24 ;
  icrl^ := vector;
end;

procedure enable_local_apic;
var
  svr: ^DWORD;
begin
  svr := Pointer(svr_reg);
  svr^ := svr^ or $100;
  Delay(10);
end;

procedure eoi_apic;
var
  tmp: ^DWORD;
begin
  tmp := Pointer(eoi_reg);
  tmp^ := 0;
  Delay(10);
end;

function SpinLock(CmpVal, NewVal: UInt64; var addval: UInt64): UInt64; assembler;
asm
  @spin:
    mov rax, cmpval
    {$IFDEF LINUX} lock cmpxchg [rdx], rsi {$ENDIF}
    {$IFDEF WINDOWS} lock cmpxchg [r8], rdx {$ENDIF}
    pause
    jnz @spin
end;

function GetApicID: Byte; inline;
begin
  Result := PDWORD(apicid_reg)^ shr 24;
end;

function GetApicBaseAddr: Pointer;
var
  basehigh, baselow: DWORD;
begin
  asm
    mov ecx, 1bh
    xor eax, eax
    xor edx, edx
    rdmsr
    mov baselow, eax
    mov basehigh, edx
  end ['ECX', 'EAX', 'EDX'];
  Result := Pointer(PtrUInt((baselow and $fffff000) or ((basehigh and $f) shr 32)));
end;


function is_apic_ready: Boolean;{$IFDEF ASMINLINE} inline; {$ENDIF}
var
  r: PDWORD;
begin
  r := Pointer(icrlo_reg) ;
  if (r^ and $1000) = 0 then
    Result := True
  else
    Result := False;
end;

procedure NOP;
asm
  nop;
  nop;
  nop;
end;

procedure Delay(ms: LongInt);
var
  tmp : ^DWORD ;
begin
  tmp := Pointer (divide_reg);
  tmp^ := $b;
  tmp := Pointer(timer_init_reg); // set the count
  tmp^ := (LocalCpuSpeed * 1000)*ms; // the count is aprox.
  tmp := Pointer (timer_curr_reg); // wait for the counter
  while tmp^ <> 0 do
  begin
    NOP;
  end;
  // send the end of interruption
  tmp := Pointer(eoi_reg);
  tmp^ := 0;
end;

procedure DelayMicro(microseg: LongInt);
var
  tmp : ^DWORD ;
begin
  tmp := Pointer (divide_reg);
  tmp^ := $b;
  tmp := Pointer(timer_init_reg); // set the count
  tmp^ := LocalCpuSpeed*microseg;
  tmp := Pointer (timer_curr_reg); // wait for the counter
  while tmp^ <> 0 do
  begin
    NOP;
  end;
  tmp := Pointer(eoi_reg); // send the end of interruption
  tmp^ := 0;
end;

procedure RelocateAPIC;
asm
  mov ecx, 27
  mov edx, 0
//  mov eax, Apic_Base
  wrmsr
end;

const
  Status_Port : array[0..1] of Byte = ($20,$A0);
  Mask_Port : array[0..1] of Byte = ($21,$A1);
  PIC_MASK: array [0..7] of Byte =(1,2,4,8,16,32,64,128);

// relocate the irq to 31-46
procedure RelocateIrqs ;
asm
  mov   al , 00010001b
  out   20h, al
  nop
  nop
  nop
  out  0A0h, al
  nop
  nop
  nop
  mov   al , 20h
  out   21h, al
  nop
  nop
  nop
  mov   al , 28h
  out  0A1h, al
  nop
  nop
  nop
  mov   al , 00000100b
  out   21h, al
  nop
  nop
  nop
  mov   al , 2
  out  0A1h, al
  nop
  nop
  nop
  mov   al , 1
  out   21h, al
  nop
  nop
  nop
  out  0A1h, al
  nop
  nop
  nop
  mov   al , 0FFh
  out   21h, al
  mov   al , 0FFh
  out  0A1h, al
end;

procedure IrqOn(irq: Byte);
begin
  if irq > 7 then
    write_portb(read_portb($a1) and (not pic_mask[irq-8]), $a1)
  else
    write_portb(read_portb($21) and (not pic_mask[irq]), $21);
end;

procedure IrqOff(irq: Byte);
begin
  if irq > 7 then
    write_portb(read_portb($a1) or pic_mask[irq-8], $a1)
  else
    write_portb(read_portb($21) or pic_mask[irq], $21);
end;

procedure eoi;
begin
  write_portb($20, status_port[0]);
  write_portb($20, status_port[1]);
end;

procedure all_irq_off;
begin
  write_portb($ff, mask_port[0]);
  write_portb($ff, mask_port[1]);
end;

function get_irq_master: Byte ;
begin
  write_portb($b, $20);
  NOP;
  Result := read_portb($20);
end;

function get_irq_slave : Byte ;
begin
  write_portb($b, $a0);
  NOP;
  Result := read_portb($a0);
end;

const
  cmos_port_reg = $70 ;
  cmos_port_rw  = $71 ;

procedure cmos_write(Data, Reg: Byte);
begin
  write_portb(Reg, cmos_port_reg);
  write_portb(Data, cmos_port_rw);
end;

function cmos_read(Reg: Byte): Byte;
begin
  write_portb(Reg, cmos_port_reg);
  Result := read_portb(cmos_port_rw);
end;

// This code has been extracted from DelphineOS <delphineos.sourceforge.net>
// Return the CPU speed in Mhz
function CalculateCpuSpeed: Word;
var
  count_lo, count_hi, family, features: DWORD;
  speed: WORD;
begin
  asm
    mov eax, 1
    cpuid
    mov features, edx
  end ['EAX', 'EDX'];

  // we verify if there is timecounter
  if (features and $10) <> $10 then
  begin
    Result := 0;
    Exit
  end;

  asm
    mov eax , 1
    cpuid
    and eax , $0f00
    shr eax , 8
    mov family , eax
    in    al , 61h
    nop
    nop
    and   al , 0FEh
    out   61h, al
    nop
    nop
    mov   al , 0B0h
    out   43h, al
    nop
    nop
    mov   al , 0FFh
    out   42h, al
    nop
    nop
    out   42h, al
    nop
    nop
    in    al , 61h
    nop
    nop
    or    al , 1
    out   61h, al
    rdtsc
    add   eax, 3000000
    adc   edx, 0
    cmp   family, 6
    jb    @TIMER1
    add   eax, 3000000
    adc   edx, 0
  @TIMER1:
    mov   count_lo, eax
    mov   count_hi, edx
  @TIMER2:
    rdtsc
    cmp   edx, count_hi
    jb    @TIMER2
    cmp   eax, count_lo
    jb    @TIMER2
    in    al , 61h
    nop
    nop
    and   al , 0FEh
    out   61h, al
    nop
    nop
    mov   al , 80h
    out   43h, al
    nop
    nop
    in    al , 42h
    nop
    nop
    mov   dl , al
    in    al , 42h
    nop
    nop
    mov   dh , al
    mov   cx , -1
    sub   cx , dx
    xor   ax , ax
    xor   dx , dx
    cmp   cx , 110
    jb    @CPUS_SKP
    mov   ax , 11932
    mov   bx , 300
    cmp   family, 6
    jb    @TIMER3
    add   bx , 300
  @TIMER3:
    mul   bx
    div   cx
    push  ax
    push  bx
    mov   ax , dx
    mov   bx , 10
    mul   bx
    div   cx
    mov   dx , ax
    pop   bx
    pop   ax
  @CPUS_SKP:
    mov speed, ax
  end ['EAX', 'EDX', 'EBX', 'ECX'];

  if speed = 0 then
  begin
    speed := MAX_CPU_SPEED_MHZ;
  end;

  Result := speed;
end;

// add "-device isa-debug-exit,iobase=0xf4,iosize=0x04"
procedure ShutdownInQemu;
begin
  write_portb(0, $f4);
end;

// reboot using keyboard
procedure Reboot;
var
  good: Byte;
begin
  good := 2;
  while good and 2 = 1 do
    good := read_portb($64);
  write_portb($FE, $64);
  hlt;
end;

function read_rdtsc: Int64;
var
  l, h: QWORD;
begin
  asm
    xor rax, rax
    xor rdx, rdx
    rdtsc
    mov l, rax
    mov h, rdx
  end ['RAX', 'RDX'];
  Result := QWORD(h shl 32) or l;
end;

function bit_test(Val: Pointer; pos: QWord): Boolean;
asm
  {$IFDEF WINDOWS} bt  [rcx], rdx {$ENDIF}
  {$IFDEF LINUX} bt [rdi], rsi {$ENDIF}
  jc  @True
  @False:
   mov rax , 0
   jmp @salir
  @True:
    mov rax , 1
  @salir:
end;

procedure bit_reset(Value: Pointer; Offset: QWord); assembler;
asm
  {$IFDEF WINDOWS} btr [rcx], rdx {$ENDIF}
  {$IFDEF LINUX} btr [rdi], rsi {$ENDIF}
end;

procedure bit_set(Value: Pointer; Offset: QWord); assembler;
asm
  {$IFDEF WINDOWS} bts [rcx], rdx {$ENDIF}
  {$IFDEF LINUX} bts [rdi], rsi {$ENDIF}
end;

procedure change_sp(new_esp: Pointer); assembler ;{$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov rsp, new_esp
  ret
end;

procedure SwitchStack(sv: Pointer; ld: Pointer); assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov [sv] , rbp
  mov rbp , [ld]
end;

type
  Int15h_info = record
    Base   : QWord;
    Length : QWord;
    tipe   : DWORD;
    Res    : DWORD;
  end;
  PInt15h_info = ^Int15h_info;

  Pmbentry = ^Tmbentry;

  Tmbentry = packed record
    Size: dword;
    Addr: qword;
    Len: qword;
    Tp: dword;
  end;

const
  INT15H_TABLE = $30000;

var
  CounterID: LongInt; // starts with CounterID = 1

function GetMemoryRegion(ID: LongInt; Buffer: PMemoryRegion): LongInt;
var
  Desc: PInt15h_info;
  DescMB: Pmbentry;
  mbp: ^DWORD;
begin
  if ID > CounterID then
    Result := 0
  else
    Result := SizeOf(TMemoryRegion);
  if mbpointer = nil then
  begin
    Desc := Pointer(INT15H_TABLE + SizeOf(Int15h_info) * (ID-1));
    Buffer.Base := Desc.Base;
    Buffer.Length := Desc.Length;
    Buffer.Flag := Desc.tipe;
  end
  else begin
    mbp := Pointer(mbpointer + 48);
    DescMB := Pointer(PtrUInt(mbp^));
    Inc(DescMB, ID-1);
    Buffer.Base := DescMB.Addr;
    Buffer.Length := DescMB.Len;
    Buffer.Flag := DescMB.Tp;
  end;
end;

// Count available memory after $100000
procedure MemoryCounterInit;
var
  Magic, maplen, mapaddr: ^DWORD;
  Desc: PInt15h_info;
  DescMB: Pmbentry;
  Count: DWORD;
begin
  CounterID := 0;
  AvailableMemory := 0;
  if mbpointer = nil then
  begin
    Magic := Pointer(INT15H_TABLE);
    Desc := Pointer(INT15H_TABLE);
    while Magic^ <> $1234 do
    begin
      if (Desc.tipe = 1) and (Desc.Base >= $100000) then
        AvailableMemory := AvailableMemory + Desc.Length;
      Inc(Magic);
      Inc(Desc);
    end;
    AvailableMemory := AvailableMemory;
    CounterID := (QWord(Magic)-INT15H_TABLE);
    CounterID := CounterID div SizeOf(Int15h_info);
  end else
  begin
    maplen := mbpointer + 44;
    mapaddr := mbpointer + 48;
    DescMB := Pointer(PtrUInt(mapaddr^));
    Count := maplen^;
    while count <> 0 do
    begin
      if (DescMB.tp = 1) and (DescMB.addr >= $100000) then
        AvailableMemory := AvailableMemory + DescMB.Len;
      Inc(DescMB);
      Inc(CounterID);
      Dec(Count, sizeof(Tmbentry));
    end;
  end;
end;

procedure Bcd_To_Bin(var val: LongInt); inline;
begin
  val := (val and 15) + ((val shr 4) * 10);
end;

procedure Now(Data: PNow);
var
  Sec, Min, Hour,
  Day, Mon, Year: LongInt;
begin
  repeat
    Sec  := Cmos_Read(0);
    Min  := Cmos_Read(2);
    Hour := Cmos_Read(4);
    Day  := Cmos_Read(7);
    Mon  := Cmos_Read(8);
    Year := Cmos_Read(9);
  until Sec = Cmos_Read(0);
  Bcd_To_Bin(Sec);
  Bcd_To_Bin(Min);
  Bcd_To_Bin(Hour);
  Bcd_To_Bin(Day);
  Bcd_To_Bin(Mon);
  Bcd_To_Bin(Year);
  if 0 >= Mon then
  begin
    Mon := Mon + 12 ;
    Year := Year + 1;
  end;
  Data.Sec := sec;
  Data.Min := min;
  Data.Hour := hour;
  Data.Month:= Mon;
  Data.Day := Day;
  if (Year < 90) then
    Data.Year := 2000 + Year
  else
    Data.Year := 1900 + Year;
end;

function SecondsBetween(const ANow: TNow;const AThen: TNow): Longint;
var
  julnow, julthen, a1, a2: LongInt;
  NowYear, NowMonth: LongInt;
  ThenYear, ThenMonth: LongInt;
begin
  a1 := (14 - ANow.Month) div 12;
  a2 := (14 - AThen.Month) div 12;
  NowMonth:= ANow.Month + 12 * a1 - 3;
  ThenMonth:= AThen.Month + 12 * a2 - 3;
  NowYear:=  ANow.Year + 4800 - a1;
  ThenYear:=  AThen.Year + 4800 - a2;
  julnow := ANow.Day + ((153 * NowMonth+2) div 5) + 365*NowYear + (NowYear div 4) - (NowYear div 100) + (NowYear div 400);
  julthen := AThen.Day + ((153*ThenMonth+2) div 5) + 365*ThenYear + (ThenYear div 4) - (ThenYear div 100) + (ThenYear div 400);
  Result := (julnow - julthen ) * 3600 * 24 + Abs(ANow.Hour - AThen.Hour) * 3600 + Abs (ANow.Min -  AThen.Min) * 60 + Abs(ANow.Sec - AThen.Sec);
end;

{$IFDEF FPC}
procedure nolose3;  [public, alias: '__FPC_specific_handler'];
begin

end;
{$ENDIF}

procedure Interruption_Ignore; {$IFDEF FPC} [nostackframe]; assembler ; {$ENDIF}
asm
  db $48, $cf
end;

procedure IRQ_Ignore; {$IFDEF FPC} [nostackframe]; assembler ; {$ENDIF}
asm
  call EOI;
  db $48, $cf
end;

procedure Apic_IRQ_Ignore; {$IFDEF FPC} [nostackframe]; assembler ; {$ENDIF}
asm
  call eoi_apic
  db $48, $cf
end;

const
 PCI_CONF_PORT_INDEX = $CF8;
 PCI_CONF_PORT_DATA  = $CFC;

function PciReadDword(const bus, device, func, regnum: UInt32): UInt32;
var
  Send: DWORD;
begin
  Send := $80000000 or (bus shl 16) or (device shl 11) or (func shl 8) or (regnum shl 2);
  write_portd(@Send, PCI_CONF_PORT_INDEX);
  read_portd(@Send, PCI_CONF_PORT_DATA);
  Result := Send;
end;

function PciReadByte(const bus, device, func: DWORD; offset: Byte): Byte;
var
  tmp, off: DWORD;
begin
  tmp := PciReadDword(bus, device, func, offset shr 2);
  off := offset mod 4;
  Result := (tmp shr (off shl 3)) and $ff;
end;

function PciReadWord(const bus, device, func, regnum: UInt32): Word;
var
  Send: DWORD;
  tmp: Word;
begin
  Send := $80000000 or (bus shl 16) or (device shl 11) or (func shl 8) or (regnum and $fc);
  write_portd(@Send, PCI_CONF_PORT_INDEX);
  tmp := read_portw(PCI_CONF_PORT_DATA);
  Result := (tmp shr ((regnum and 2) * 8 )) and $ffff;
end;

procedure PciWriteWord (const bus, device, func, regnum, value: Word);
var
  Send: DWORD;
begin
  Send := $80000000 or (bus shl 16) or (device shl 11) or (func shl 8) or (regnum and $fc);
  write_portd(@Send, PCI_CONF_PORT_INDEX);
  write_portw(value, PCI_CONF_PORT_DATA);
end;

// Initialize SSE and SSE2 extensions
// Do this for every core
// TODO : Floating-Point exception is ignored
{$IFDEF FPC}
procedure SSEInit; assembler;
asm
  xor rax , rax
  // set OSFXSR bit
  mov rax, cr4
  or ah , 10b
  mov cr4 , rax
  xor rax , rax
  mov rax, cr0
  // clear MP and EM bit
  and al ,11111001b
  mov cr0 , rax
end;
{$ENDIF}
{$IFDEF DCC}
procedure SSEInit; assembler;
asm
  xor rax , rax
  // set OSFXSR bit
  mov eax, cr4
  or ah , 10b
  mov cr4 , eax
  xor rax , rax
  mov eax, cr0
  // clear MP and EM bit
  and al ,11111001b
  mov cr0 , eax
end;
{$ENDIF}

var
  esp_tmp: Pointer; // Pointer to Stack for each CPU during SMP Initialization
  start_stack: array [0..MAX_CPU-1] of array [1..size_start_stack] of Byte; // temporary stack for each CPU

{$IFDEF FPC}

procedure boot_confirmation;
var
  CpuID: Byte;
begin
  enable_local_apic;
  CpuID := GetApicID;
  Cores[CPUID].InitConfirmation := True;
  Cores[CPUID].InitProc;
end;

// Stack for BSP
var
  stack : array[1..5000] of Byte ;

const
  pstack: Pointer = @stack[5000] ;

procedure InitCpu; assembler;
asm
  mov rax, Kernel_Data_Sel
  mov ss, ax
  mov es, ax
  mov ds, ax
  mov gs, ax
  mov fs, ax
  mov rsp, esp_tmp
  mov rax, PDADD
  {$IFDEF FPC} mov cr3, rax {$ENDIF}
  {$IFDEF DCC} mov cr3, eax {$ENDIF}
  xor rbp, rbp
  sti
  call SSEInit
  call boot_confirmation
end;

// Entry point of PE64 EXE
// This procedure is executed in parallel by all CPUs when booting
procedure main; [public, alias: '_mainCRTStartup']; assembler;
asm
  mov rax, cr3 // Cannot remove this warning! using eax generates error at compile-time.
  cmp rax, 90000h  // rax = $100000 when executed the first time from the bootloader (debugged once using FPC version)
  je InitCpu
  mov rsp, pstack
  xor rbp, rbp
  mov mbpointer, rbx
  call KernelStart
end;
{$ENDIF}

// Boot CPU using IPI messages.
function InitCore(ApicID: Byte): Boolean;
begin
  Result := True;
  // wakeup the remote core with IPI-INIT
  send_apic_init(apicid);
  Delay(10);
  // send the first startup
  send_apic_startup(ApicID, 2);
  Delay(10);
  // remote CPU has read the IPI?
  if not is_apic_ready then
  begin
    Delay(100);
    if not is_apic_ready then
    begin
     Result := False;
     Exit;
    end;
  end;
  send_apic_startup(ApicID, 2);
  Delay(10);
  esp_tmp := Pointer(SizeUInt(esp_tmp) - size_start_stack);
end;

// Detect APICs on MP table
procedure mp_apic_detect(table: p_mp_table_header);
var
  m: ^Byte;
  I: LongInt;
  cp: p_mp_processor_entry ;
begin
  m := Pointer(SizeUInt(table) + SizeOf(mp_table_header));
  I := 0;
  while I < table.count do
  begin
    if (m^  = cpu_type) and (CPU_COUNT < MAX_CPU-1) then
    begin
      cp := Pointer(m);
      Inc(CPU_COUNT);
      Cores[cp.Apic_id].ApicID := cp.Apic_id;
      Cores[cp.Apic_id].Present := True;
      m := Pointer(SizeUInt(m)+SizeOf(mp_processor_entry));
      // boot core doesn't need initialization
      if (cp.flags and 2 ) = 2 then
      begin
        Cores[cp.Apic_id].CpuBoot := True;
        Cores[cp.Apic_id].InitConfirmation := True;
	Cores[cp.Apic_id].Present := True;
      end;
    end else
    begin
      m := Pointer(SizeUInt(m)+SizeOf(mp_apic_entry));
    end;
    Inc(I);
  end;
end;

// look for the ACPI version 1.4
procedure mp_table_detect;
var
  find: p_mp_floating_struct;
begin
  find := Pointer(MP_START_ADD) ;
  while SizeUInt(find) < $fffff do
  begin
    if (find.signature[0]='_') and (find.signature[1]='M') then
    begin
      if SizeUInt(find.phys) <> 0 then
      begin
        mp_apic_detect(Pointer(SizeUint(find.phys)));
        Exit;
      end;
      Exit;
    end;
    Inc(find);
   end;
end;

type
  TAcpiRsdp = packed record
    Signature: array[0..7] of XChar;
    Checksum: Byte;
    oem_id:array[0..5] of Byte;
    Revision: Byte;
    rsdt_address: DWORD;
    Length: DWORD;
    xsdt_address: QWord;
    ext_checksum: Byte;
    Reserved: array[0..2] of Byte;
  end;
  PAcpiRsdp = ^TAcpiRsdp;

  TAcpiTableHeader = packed record
    Signature: array[0..3] of XChar;
    Length: DWORD;
    Revision: Byte;
    Checksum: Byte;
    oem_id: array[0..5] of XChar;
    oem_table_id : array[0..7] of XChar;
    oem_revision: DWORD;
    asl_compiler_id:array[0..3] of XChar;
    asl_compiler_revision: DWORD;
  end;
  PAcpiTableHeader = ^TAcpiTableHeader;

  TAcpiRstd = packed record
    Header: TAcpiTableHeader;
    Entry: array[0..8] of DWORD;
  end;
  PAcpiRstd = ^TAcpiRstd;

  TAcpiMadt = packed record
    Header: TAcpiTableHeader;
    ApicAddr: DWORD;
    Res: DWORD;
  end;
  PAcpiMadt = ^TAcpiMadt;

  TAcpiMadtEntry = packed record
    nType: Byte;
    Length: Byte;
  end;
  PAcpiMadtEntry = ^TAcpiMadtEntry;

  TAcpiMadtProcessor = packed record
    Header: TAcpiMadtEntry;
    AcpiId: Byte;
    ApicId: Byte;
    Flags: DWORD;
  end;
  PAcpiMadtProcessor = ^TAcpiMadtProcessor;

procedure acpi_table_detect;
var
  Counter, J: LongInt;
  Entry: PAcpiMadtEntry;
  madt: PAcpiMadt;
  MadEnd: Pointer;
  P: PChar;
  Processor: PAcpiMadtProcessor;
  RSDP: PAcpiRsdp;
  RSTD: PAcpiRstd;
  TableHeader: PAcpiTableHeader;
begin
  P := Pointer($e0000);
  while p < Pointer($100000) do
  begin
    // looking for RSD sign
    if (p[0] = 'R') and (p[1]='S') and (p[2]='D') then
    begin
      RSDP :=  Pointer(p);
      // maybe some sing detection on RSTD
      RSTD := Pointer(QWord(RSDP.rsdt_address));
      // number of entries in table
      Counter:= (RSTD.Header.Length - SizeOf(TAcpiTableHeader)) div 4;
      for J := 0 to Counter-1 do
      begin
        TableHeader := Pointer(QWord(RSTD.Entry[j])); // table header
        // look for the "APIC" signature
        if (TableHeader.Signature[0] = 'A') and (TableHeader.Signature[1] = 'P')  then
        begin
          madt := Pointer(TableHeader);
          MadEnd := Pointer(SizeUInt(madt) + TableHeader.Length);
          Entry := Pointer(SizeUInt(madt) + SizeOf(TAcpiMadt));
          while SizeUInt(Entry) < SizeUInt(MadEnd) do
          begin // that 's a new Processor.
            if Entry.nType=0 then
            begin
              Processor := Pointer(Entry);
              // Is Processor Enabled ??
              if Processor.flags and 1 = 1 then
              begin
                Inc(CPU_COUNT);
                Cores[Processor.apicid].ApicID := Processor.apicid;
                Cores[Processor.apicid].Present := True;
                // CPU#0 is a BOOT cpu
                if Processor.apicid = 0 then
                begin
                  Cores[Processor.apicid].CPUBoot := True;
                  Cores[Processor.apicid].InitConfirmation := True;
		  Cores[Processor.apicid].Present := True;
                end;
              end;
            end;
            Entry := Pointer(SizeUInt(Entry) + Entry.Length);
          end;
        end;
      end;
      Break;
    end;
    Inc(P, 16);
  end;
end;

// Detect all Cores using MP's Intel tables and ACPI Tables.
procedure SMPInitialization;
var
  J: LongInt;
begin
  for J :=0 to MAX_CPU-1 do
  begin // clear fields
    Cores[J].Present := False;
    Cores[J].CPUBoot:= False;
    Cores[J].ApicID := 0;
    Cores[J].InitConfirmation := False;
    Cores[J].InitProc := nil;
  end;
  CPU_COUNT := 0;
  acpi_table_detect; // ACPI detection
  if CPU_COUNT = 0 then
    mp_table_detect; // if cpu_count is zero then use a MP Tables
  if CPU_COUNT = 0 then
    CPU_COUNT := 1;
  // setting boot core
  Cores[0].Present := True;
  Cores[0].CPUBoot := True;
  Cores[0].ApicID := GetApicID;
  Cores[0].InitConfirmation := True;
  // temporary stack used to initialize every Core
  esp_tmp := @start_stack[MAX_CPU-1][size_start_stack];
end;

var
  PML4_Table: PDirectoryPage;

// Refresh the TLB's Cache
procedure FlushCr3; assembler;
asm
  mov rax, PDADD
  {$IFDEF FPC} mov cr3, rax {$ENDIF}
  {$IFDEF DCC} mov cr3, eax {$ENDIF}
end;

// Set Page as cacheable
// "Add" points to the page, It's a multiple of 2MB (Page Size)
procedure SetPageCache(Add: Pointer);
var
  I_PML4,I_PPD,I_PDE: LongInt;
  PDD_Table, PDE_Table, Entry: PDirectoryPage;
  Page: QWord;
begin
  Page := QWord(Add);
  I_PML4:= Page div 512*1024*1024*1024;
  I_PPD := (Page div (1024*1024*1024)) mod 512;
  I_PDE := (Page div (1024*1024*2)) mod 512;
  Entry:= Pointer(SizeUInt(PML4_Table) + SizeOf(TDirectoryPageEntry)*I_PML4);
  PDD_Table := Pointer((entry.PageDescriptor shr 12)*4096);
  Entry := Pointer(SizeUInt(PDD_Table) + SizeOf(TDirectoryPageEntry)*I_PPD);
  PDE_Table := Pointer((Entry.PageDescriptor shr 12)*4096);
  // 2 MB page's entry
  // PCD bit is Reset --> Page In Cached
  Bit_Reset(Pointer(SizeUInt(PDE_Table) + SizeOf(TDirectoryPageEntry)*I_PDE), 4);
end;

// Set Page as not-cacheable
// "Add" is Pointer to page, It's a multiple of 2MB (Page Size)
procedure RemovePageCache(Add: Pointer);
var
  I_PML4,I_PPD,I_PDE: LongInt;
  PDD_Table, PDE_Table, Entry: PDirectoryPage;
  page: QWord;
begin
  page:= QWord(Add);
  I_PML4:= Page div 512*1024*1024*1024;
  I_PPD := (Page div (1024*1024*1024)) mod 512;
  I_PDE := (Page div (1024*1024*2)) mod 512;
  Entry:= Pointer(SizeUInt(PML4_Table) + SizeOf(TDirectoryPageEntry)*I_PML4);
  PDD_Table := Pointer((Entry.PageDescriptor shr 12)*4096);
  Entry := Pointer(SizeUInt(PDD_Table) + SizeOf(TDirectoryPageEntry)*I_PPD);
  PDE_Table := Pointer((Entry.PageDescriptor shr 12)*4096);
  // 2 MB page's entry
  // PCD bit is Reset --> Page is cached
  Bit_Set(Pointer(SizeUInt(PDE_Table) + SizeOf(TDirectoryPageEntry)*I_PDE),4);
end;


// Set Page as Read Only
// "Add" is Pointer to page, It's a multiple of 2MB (Page Size)
procedure SetPageReadOnly(Add: Pointer);
var
  I_PML4,I_PPD,I_PDE: LongInt;
  PDD_Table, PDE_Table, Entry: PDirectoryPage;
  Page: QWord;
begin
  Page := QWord(Add);
  I_PML4:= Page div 512*1024*1024*1024;
  I_PPD := (Page div (1024*1024*1024)) mod 512;
  I_PDE := (Page div (1024*1024*2)) mod 512;
  Entry:= Pointer(SizeUInt(PML4_Table) + SizeOf(TDirectoryPageEntry)*I_PML4);
  PDD_Table := Pointer((entry.PageDescriptor shr 12)*4096);
  Entry := Pointer(SizeUInt(PDD_Table) + SizeOf(TDirectoryPageEntry)*I_PPD);
  PDE_Table := Pointer((Entry.PageDescriptor shr 12)*4096);
  // 2 MB page's entry
  Bit_Reset(Pointer(SizeUInt(PDE_Table) + SizeOf(TDirectoryPageEntry)*I_PDE), 1);
end;

procedure CacheManagerInit;
var
  Page: Pointer;
begin
  Page := nil;
  PML4_Table := Pointer(PDADD);
  // first two pages aren't cacheable (0-2*PAGE_SIZE)
  RemovePageCache(Page);
  // first page is read only
  SetPageReadOnly(Page);
  Page := Pointer(SizeUInt(Page) + PAGE_SIZE);
  RemovePageCache(Page);
  FlushCr3;
end;

// NOTE: addr must be set as a write-back memory
procedure monitor(addr: Pointer; ext: DWORD; hint: DWORD);
begin
  if LargestMonitorLine <> 0 then
  begin
    asm
     mov rax, addr
     mov ecx, ext
     mov edx, hint
     monitor
    end ['RAX', 'ECX', 'EDX'];
  end;
end;

// NOTE: processor has to support mwait/monitor instrucctions
procedure mwait(ext: DWORD; hint: DWORD);
begin
  if LargestMonitorLine <> 0 then
  begin
    asm
      mov ecx, ext
      mov eax, hint
      mwait
    end ['ECX', 'EAX']
  // halt if mwait is not supported
  end else
  begin
    asm
     hlt
    end;
  end;
end;

// Check if Monitor/MWait is supported
procedure MWaitInit;
begin
  asm
    mov eax, 05h
    cpuid
    mov LargestMonitorLine, ebx
    mov SmallestMonitorLine, eax
  end ['EAX', 'EBX'];
end;

procedure hlt;assembler;
asm
  hlt
end;

procedure ReadBarrier;assembler;nostackframe;{$ifdef SYSTEMINLINE}inline;{$endif}
asm
  lfence
end;

procedure ReadWriteBarrier;assembler;nostackframe;{$ifdef SYSTEMINLINE}inline;{$endif}
asm
  mfence
end;

procedure WriteBarrier;assembler;nostackframe;{$ifdef SYSTEMINLINE}inline;{$endif}
asm
  sfence
end;

function GetKernelParam(I: LongInt): Pchar;
var
  tmp: Pchar;
begin
  tmp := KernelParam;
  while (tmp^ <> #0) and (I > 0) do
  begin
    If tmp^ = ' ' then
    begin
      Dec(I);
    end;
    Inc(tmp);
  end;
  Result := tmp;
end;

procedure ArchInit;
var
  I: LongInt;
  tmp: ^DWORD;
  p: PChar;
begin
  idt_gates := Pointer(IDTADDRESS);
  FillChar(PChar(IDTADDRESS)^, SizeOf(TInteruptGate)*256, 0);
  if mbpointer <> Nil then
  begin
    tmp := mbpointer + 16;
    p := PChar(PtrUInt(tmp^));
    KernelParam := Pointer(Kernel_Param);
    while p^ <> #0 do
    begin
      KernelParam^ := p^;
      Inc(KernelParam);
      Inc(p);
    end;
    KernelParam^ := #0; 
    KernelParam := Pointer(Kernel_Param); 
  end;
  RelocateIrqs;
  MemoryCounterInit;
  CacheManagerInit;
  LocalCpuSpeed := PtrUInt(CalculateCpuSpeed);
  IrqOn(2);
  for I := 33 to 47 do
    CaptureInt(I, @IRQ_Ignore);
  for I := 0 to 32 do
    CaptureInt(I, @Interruption_Ignore);
  CaptureInt(INTER_CORE_IRQ, @Apic_IRQ_Ignore);
  EnableInt;
  Now(@StartTime);
  enable_local_apic;
  SMPInitialization;
  SSEInit;
  MWaitInit;
end;

end.

