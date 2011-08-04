//
// Network.pas
//
// Manipulation of Packets and Network Interface
// Implements TCP-IP Stack and socket structures.
//
// Notes :
// - Every Network resource is dedicated to one CPU, the programmer must dedicate the resource
// - Only major Sockets Syscalls are implemented at this time
//
// Changes :
// 17 / 08 / 2009 : Multiplex-IO implemented at the level of kernel. First Version.
//                  by Matias E. Vara.
// 24 / 03 / 2009 : SysMuxSocketSelect() , Select() with MultiplexIO .
// 26 / 12 / 2008 : Packet-Cache was removed and replaced with a most simple way.
//                  Solved bugs in Size of packets and support multiples connections.
// 31 / 12 / 2007 : First Version by Matias E. Vara
//
// Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
// All Rights Reserved
//
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

unit Network;

interface

{$I Toro.inc}

uses
  Arch, Process, Console, Memory, Debug;

const
  // Sockets Types
  SOCKET_DATAGRAM = 1; // For datagrams like UDP
  SOCKET_STREAM = 2; // For connections like TCP
  MAX_SocketPORTS = 10000; // Max number of ports supported
  MAX_WINDOW = $4000; // Max Window Size
  MTU = 1200; // MAX Size of packet for TCP Stack
  USER_START_PORT = 7000; // First PORT used by GetFreePort
  SZ_SocketBitmap = (MAX_SocketPORTS - USER_START_PORT) div SizeOf(Byte)+1; // Size of Sockets Bitmaps
  // Max Time that Network Card can be Inactive with packet in a Buffer,  in ms
  // TODO: This TIMER wont be necessary
  MAX_TIME_SENDER = 50;

type
  PNetworkInterface = ^TNetworkInterface;
  PPacket = ^TPacket;
  PEthHeader= ^TEthHeader;
  PArpHeader = ^TArpHeader;
  PIPHeader= ^TIPHeader;
  PTCPHeader= ^TTCPHeader;
  PUDPHeader = ^TUDPHeader;
  PSocket = ^TSocket;
  PMachine = ^TMachine;
  PICMPHeader = ^TICMPHeader;
  PNetworkService = ^TNetworkService;
  PNetworkHandler = ^TNetworkHandler;
  PBufferSender = ^TBufferSender;
  THardwareAddress = array[0..5] of Byte; // MAC Address
  TIPAddress = DWORD; // IP v4

  TEthHeader = packed record
    Destination: THardwareAddress ;
    Source : THardwareAddress ;
    ProtocolType: Word;
  end;

  TArpHeader =  packed record
    Hardware: Word;
    Protocol: Word;
    HardwareAddrLength: Byte;
    ProtocolAddrLength: Byte;
    OpCode: Word;
    SenderHardAddr: THardwareAddress ;
    SenderIpAddr: TIPAddress;
    TargetHardAddr: THardwareAddress ;
    TargetIpAddr: TIPAddress;
  end;

  TIPHeader = packed record
    VerLen       : Byte;
    TOS          : Byte;
    PacketLength : Word;
    ID           : Word;
    Flags        : Byte;
    FragmentOfs  : Byte;
    TTL          : Byte;
    Protocol     : Byte;
    Checksum     : Word;
    SourceIP     : TIPAddress;
    DestIP       : TIPAddress;
  end;

  TTCPHeader = packed record
    SourcePort, DestPort: Word;
    SequenceNumber: DWORD;
    AckNumber: DWORD;
    Header_Length: Byte;
    Flags: Byte;
    Window_Size: Word;
    Checksum: Word;
    UrgentPointer: Word;
  end;

  TUDPHeader = packed record
    ID: Word;
    SourceIP, DestIP: TIPAddress;
    SourcePort, DestPort: Word;
    PacketLength: Word;
    checksum: Word;
  end;

  TICMPHeader = packed record
    tipe: Byte;
    code: Byte;
    checksum: Word;
    id: Word;
    seq: Word;
  end;

  TPacket = record // managed by Packet-Cache
    Size: LongInt;
    Data: Pointer;
    Status: Boolean; // result of transmition
    Ready: Boolean; // only for the kernel , the packet was sent
    Delete: Boolean; // Special Packet can be deleted
    Next: PPacket;  // only for the kernel
  end;
  
  // Entry in Translation Table
  TMachine = record
    IpAddress: TIpAddress;
    HardAddress: THardwareAddress;
    Next: PMachine;
  end;
   
  TNetworkInterface = record
    Name: AnsiString; // Name of interface
    Minor: LongInt; // Internal Identificator
    MaxPacketSize: LongInt; // Max size of packet
    HardAddress: THardwareAddress; // MAC Address
    // Packets from physical layer.
    IncomingPackets: PPacket;
    OutgoingPackets: PPacket;
    // Handlers of drivers
    Start: procedure (NetInterface: PNetworkInterface);
    Send: procedure (NetInterface: PNetWorkInterface;Packet: PPacket);
    Reset: procedure (NetInterface: PNetWorkInterface);
    Stop: procedure (NetInterface: PNetworkInterface);
    CPUID: LongInt; // CPUID for which is dedicated this Network Interface Card
    TimeStamp: Int64;
    Next: PNetworkInterface;
  end;

  TNetworkDedicate = record
    NetworkInterface: PNetworkInterface; // Hardware Driver
    IpAddress: TIPAddress; // Internet Protocol Address
    Gateway: TIPAddress;
    Mask: TIPAddress;
    TranslationTable: PMachine;
    // Table of Sockets sorted by port
    // Sockets for conections
    SocketStream: array[0..MAX_SocketPORTS-1] of PNetworkService;
    SocketStreamBitmap: array[0..SZ_SocketBitmap] of Byte;
    // Sockets for Datagram
    SocketDatagram: array[0..MAX_SocketPORTS-1] of PNetworkService;
    SocketDatagramBitmap: array[0..SZ_SocketBitmap] of Byte;
  end;
  PNetworkDedicate = ^TNetworkDedicate;

  PSockAddr = ^TSockAddr;
  TSockAddr = record
    case Integer of
      0: (sin_family: Word;
          sin_port: Word;
          sin_addr: TIPAddress;
          sin_zero: array[0..7] of XChar);
      1: (sa_family: Word;
          sa_data: array[0..13] of XChar)
  end;
  TInAddr = TIPAddress;

  // Socket structure
  TSocket = record
    SourcePort,DestPort: LongInt;
    DestIp: TIPAddress;
    SocketType: LongInt;
    Mode: LongInt;
    State: LongInt;
    LastSequenceNumber: UInt32;
    LastAckNumber: LongInt;
    RemoteWinLen: UInt32;
    RemoteWinCount: UInt32;
    BufferReader: PChar;
    BufferLength: UInt32;
    Buffer: PChar;
    ConnectionsQueueLen: LongInt;
    ConnectionsQueueCount: LongInt;
    PacketReading: PPacket;
    PacketReadCount: LongInt;
    PacketReadOff: Pointer;
    NeedFreePort: Boolean;
    DispatcherEvent: LongInt;
    TimeOut:Int64;
    Counter: Int64;
    BufferSender: PBufferSender;
    AckFlag: Boolean;
    AckTimeOut: LongInt;
    WinFlag: Boolean;
    WinTimeOut: LongInt;
    WinCounter: LongInt;
    Next: PSocket;
  end;

  // Network Service Structure
  TNetworkService = record
    ServerSocket: PSocket;
    ClientSocket: PSocket;
  end;

  // Network Service event handler
  TNetworkHandler = record
    DoInit: procedure;
    DoAccept: function (Socket: PSocket): LongInt;
    DoTimeOUT: function (Socket: PSocket): LongInt;
    DoReceive: function (Socket: PSocket): LongInt;
    DoConnect: function (Socket: PSocket): LongInt;
    DoConnectFail: function (Socket: PSocket): LongInt;
    DoClose: function (Socket: PSocket): LongInt;
  end;

  // Structure used for send a packet at TCP Layer
  TBufferSender = record
    Packet: PPacket;
    Attempts: LongInt;
    Counter: Int64;
    NextBuffer: PBufferSender;
  end;

//
// Socket APIs
//
procedure SysRegisterNetworkService(Handler: PNetworkHandler);
function SysSocket(SocketType: LongInt): PSocket;
function SysSocketBind(Socket: PSocket; IPLocal, IPRemote: TIPAddress; LocalPort: LongInt): Boolean;
procedure SysSocketClose(Socket: PSocket);
function SysSocketConnect(Socket: PSocket): Boolean;
function SysSocketListen(Socket: PSocket; QueueLen: LongInt): Boolean;
function SysSocketPeek(Socket: PSocket; Addr: PChar; AddrLen: UInt32): LongInt;
function SysSocketRecv(Socket: PSocket; Addr: PChar; AddrLen, Flags: UInt32) : LongInt;
function SysSocketSend(Socket: PSocket; Addr: PChar; AddrLen, Flags: UInt32): LongInt;
function SysSocketSelect(Socket:PSocket;TimeOut: LongInt):Boolean;

procedure NetworkInit; // used by kernel

// Network Interface Driver
procedure RegisterNetworkInterface(NetInterface: PNetworkInterface);
function DequeueOutgoingPacket: PPacket; // Called by ne2000irqhandler.Ne2000Handler
procedure EnqueueIncomingPacket(Packet: PPacket); // Called by ne2000irqhandler.Ne2000Handler.ReadPacket
procedure SysNetworkSend(Packet: PPacket);
function SysNetworkRead: PPacket;
function GetLocalMAC: THardwareAddress;

// primitive for programmer to register a NIC
procedure DedicateNetwork(const Name: AnsiString; const IP, Gateway, Mask: array of Byte; Handler: TThreadFunc);

implementation

var
  DedicateNetworks: array[0..MAX_CPU-1] of TNetworkDedicate;
  NetworkInterfaces: PNetworkInterface;

const
  IPv4_VERSION_LEN = $45;

  // Ethernet Packet type
  ETH_FRAME_IP = $800;
  ETH_FRAME_ARP = $806;

  // ICMP Packet type
  ICMP_ECHO_REPLY = 0;
  ICMP_ECHO_REQUEST = 8;

   // IP packet type
  IP_TYPE_ICMP = 1;
  IP_TYPE_UDP = $11;
  IP_TYPE_TCP = 6;

  // TCP flags
  TCP_SYN =2;
  TCP_SYNACK =18;
  TCP_ACK =16;
  TCP_FIN=1;
  TCP_ACKPSH = $18;
  TCP_ACKEND = TCP_ACK or TCP_FIN;
  TCP_RST = 4 ;

  MAX_ARPENTRY=100; // Max number of entries in ARP Table

  // Socket State
  SCK_BLOCKED = 0;
  SCK_LISTENING = 1;
  SCK_NEGOTIATION = 2;
  SCK_CONNECTING = 6;
  SCK_TRANSMITTING = 3;
  SCK_LOCALCLOSING = 5;
  SCK_PEER_DISCONNECTED = 9;
  SCK_CLOSED = 4;

  // Socket Mode
  MODE_SERVER = 1;
  MODE_CLIENT = 2;

  // Time for wait ACK answer, 50 miliseg per connection
  WAIT_ACK = 50;
  // Time for wait ARP Responsep
  WAIT_ARP = 50;
  // Time for wait a Remote Close , 10 seg. per connection
  WAIT_ACKFIN = 10000;

  // Times that is repeat the operation
  MAX_RETRY = 2;

  // Time for realloc memory for remote Window
  WAIT_WIN = 30000;

  // Socket Dispatcher State
  // Of sockets Clients
  DISP_ACCEPT = 1;
  DISP_WAITING = 0;
  DISP_TIMEOUT = 4;
  DISP_RECEIVE = 2;
  DISP_CONNECT = 3;
  DISP_CLOSE = 5;
  DISP_ZOMBIE = 6;

var
  LastId: WORD = 0; // used for ID packets
 
// Translate IP Address to MAC Address
function LookIp(IP: TIPAddress):PMachine;
var
  CPUID: LongInt;
  Machine: PMachine;
begin
  CPUID := GetApicid;
  Machine := DedicateNetworks[CPUID].TranslationTable;
  while Machine <> nil do
  begin
    if Machine.IpAddress = IP then
    begin
      Result := Machine;
      Exit;
    end else
      Machine := Machine.Next;
  end;
  Result := nil;
end;

// Add new entry in IP-MAC Table
procedure AddTranslateIp(IP: TIPAddress; const HardAddres: THardwareAddress);
var
  CPUID: LongInt;
  Machine: PMachine;
begin
  Machine := LookIp(Ip);
  CPUID := GetApicid;
  if Machine = nil then
  begin
    Machine := ToroGetMem(SizeOf(TMachine));
    Machine.IpAddress := Ip;
    Machine.HardAddress := HardAddres;
    Machine.Next := DedicateNetworks[CPUID].TranslationTable;
    DedicateNetworks[CPUID].TranslationTable := Machine;
  end;
end;

// Convert [192.168.1.11] to native IPAddress
procedure _IPAddress(const Ip: array of Byte; var Result: TIPAddress);
begin
  Result := (Ip[3] shl 24) or (Ip[2] shl 16) or (Ip[1] shl 8) or Ip[0];
end;

// The interface is added in Network Driver list
procedure RegisterNetworkInterface(NetInterface: PNetworkInterface);
begin
  NetInterface.Next := NetworkInterfaces;
  NetInterface.CPUID := -1;
  NetworkInterfaces := NetInterface;
end;

function SwapWORD(n: Word): Word; {$IFDEF INLINE}inline;{$ENDIF}
begin
  Result := ((n and $FF00) shr 8) or ((n and $FF) shl 8);
end;

function SwapDWORD(D: DWORD): DWORD;{$IFDEF INLINE}inline;{$ENDIF}
var
  r1, r2: packed array[1..4] of Byte;
begin
  Move(D, r1, 4);
  r2[1] := r1[4];
  r2[2] := r1[3];
  r2[3] := r1[2];
  r2[4] := r1[1];
  Move(r2, D, 4);
  SwapDWORD := D;
end;

// Return a Valid Checksum Code for IP Packet
function CalculateChecksum(pip: Pointer; data: Pointer; cnt, pipcnt: word): word;
//type
//  PByte = ^Byte;
var
  pw: ^Word;
  loop: word;
  x, w: word;
  csum: LongInt;
begin
  CalculateChecksum := 0;
  csum := 0;
  if cnt = 0 then
    Exit;
  loop := cnt shr 1;
  if pip <> nil then
  begin
    pw := pip;
    x := 1;
    while x <= PipCnt div 2 do
    begin
      csum := csum + pw^;
      inc(pw);
      Inc(x);
    end;
  end;
  pw := data;
  x := 1;
  while x <= loop do
  begin
    csum := csum + pw^;
    inc(pw);
    Inc(x);
  end;
  if (cnt mod 2 = 1) then
  begin
    w := PByte(pw)^;
    csum := csum + w;
  end;
  csum := (csum mod $10000) + (csum div $10000);
  csum := csum + (csum shr 16);
  Result := Word(not csum);
end;

type
  TPseudoHeader = packed record
    SourceIP: TIPAddress;
    TargetIP: TIPAddress;
    Cero: Byte;
    Protocol: Byte;
    TCPLen: WORD;
  end;

// Calculate CheckSum code for TCP Packet
function TCP_Checksum(SourceIP, DestIp: TIPAddress; PData: PChar; Len: Word): WORD;
var
  PseudoHeader: TPseudoHeader;
begin
  // Set-up the psueudo-header }
  FillChar(PseudoHeader, SizeOf(PseudoHeader), 0);
  PseudoHeader.SourceIP := SourceIP;
  PseudoHeader.TargetIP := DestIP;
  PseudoHeader.TCPLen := Swap(Word(Len));
  PseudoHeader.Cero := 0;
  PseudoHeader.Protocol := IP_TYPE_TCP;
  // Calculate the checksum }
  TCP_Checksum := CalculateChecksum(@PseudoHeader,PData,Len, SizeOf(PseudoHeader));
end;

// Validate new Packet to Local Socket
function ValidateTCP(IpSrc:TIPAddress;SrcPort,DestPort: Word): PSocket;
var
  Service: PNetworkService;
begin
  Service := DedicateNetworks[GetApicid].SocketStream[DestPort];
  if Service = nil then
  begin // there is no connection
    Result := nil;
    Exit;
  end;
  Result := Service.ClientSocket;
  while Result <> nil do
  begin // The TCP packet is for this connection ?
    if (Result.DestIp = IpSrc) and (Result.DestPort = SrcPort) and (Result.SourcePort = DestPort) then
      Exit
    else
      Result := Result.Next;
  end;
end;

// Set a TimeOut on Socket using the Dispatcher
procedure SetSocketTimeOut(Socket:PSocket;TimeOut:Int64); inline;
begin
  Socket.TimeOut:= TimeOut*LocalCPUSpeed*1000;
  Socket.Counter := read_rdtsc;
  Socket.DispatcherEvent := DISP_WAITING;
end;

procedure TCPSendPacket(Flags: LongInt; Socket: PSocket); forward;

// Enqueue Request for Connection to Local Socket
// Called by ProcessNetworksPackets\ProcessIPPacket
procedure EnqueueTCPRequest(Socket: PSocket; Packet: PPacket);
var
  Buffer: Pointer;
  ClientSocket: PSocket;
  EthHeader: PEthHeader;
  IPHeader: PIPHeader;
  LocalPort: Word;
  Service: PNetworkService;
  TCPHeader: PTCPHeader;
begin
  if Socket.State <> SCK_LISTENING then
  begin
    ToroFreeMem(Packet);
    Exit;
  end;
  EthHeader:= Packet.Data;
  IPHeader:= Pointer(PtrUInt(EthHeader) + SizeOf(TEthHeader));
  TCPHeader:= Pointer(PtrUInt(IPHeader) + SizeOf(TIPHeader));
  LocalPort:= SwapWORD(TCPHeader.DestPort);
  // We have the max number of request for connections
  if Socket.ConnectionsQueueLen = Socket.ConnectionsQueueCount then
  begin
    {$IFDEF DebugNetwork}DebugTrace('EnqueueTCPRequest: Fail connection to %d Queue is complete', 0, LocalPort, 0);{$ENDIF}
    ToroFreeMem(Packet);
    Exit;
  end;
  // Information about Request Machine
  // Network Service Structure
  Service := DedicateNetworks[GetApicid].SocketStream[LocalPort];
  // Alloc memory for new socket
  ClientSocket := ToroGetMem(SizeOf(TSocket));
  if ClientSocket=nil then
  begin
   ToroFreeMem(Packet);
   {$IFDEF DebugNetwork}DebugTrace('EnqueueTCPRequest: Fail connection to %d not memory', 0, LocalPort, 0);{$ENDIF}
   Exit;
  end;

  // Window Buffer for new Socket
  Buffer:= ToroGetMem(MAX_WINDOW);
  if Buffer= nil then
  begin
    ToroFreeMem(ClientSocket);
    ToroFreeMem(Packet);
    {$IFDEF DebugNetwork}DebugTrace('EnqueueTCPRequest: Fail connection to %d not memory', 0, LocalPort, 0);{$ENDIF}
    Exit;
  end;
  // Create a new connection
  ClientSocket.State := SCK_NEGOTIATION;
  ClientSocket.BufferLength := 0;
  ClientSocket.Buffer := Buffer;
  ClientSocket.BufferReader := ClientSocket.Buffer;
  // Enqueue the socket to Network Service Structure
  ClientSocket.Next := Service.ClientSocket;
  Service.ClientSocket := ClientSocket;
  ClientSocket.SocketType := SOCKET_STREAM;
  ClientSocket.Mode := MODE_CLIENT;
  ClientSocket.SourcePort := Socket.SourcePort;
  ClientSocket.DestPort := SwapWORD(TcpHeader.SourcePort);
  ClientSocket.DestIp := IpHeader.SourceIP;
  ClientSocket.LastSequenceNumber := 300;
  ClientSocket.LastAckNumber := SwapDWORD(TCPHeader.SequenceNumber)+1 ;
  ClientSocket.RemoteWinLen := SwapWORD(TCPHeader.Window_Size);
  ClientSocket.RemoteWinCount := ClientSocket.RemoteWinLen;
  ClientSocket.NeedFreePort := False;
  ClientSocket.AckTimeOUT := 0;
  AddTranslateIp(IpHeader.SourceIp, EthHeader.Source);
  // we don't need the packet
  ToroFreeMem(Packet);
  // Increment the queue of new connections
  Socket.ConnectionsQueueCount := Socket.ConnectionsQueueCount+1;
  // Send the SYNACK confirmation
  // Now , the socket waits in NEGOTIATION State for the confirmation with Remote ACK
  TCPSendPacket(TCP_SYNACK, ClientSocket);
  SetSocketTimeOut(ClientSocket, WAIT_ACK);
  {$IFDEF DebugNetwork}DebugTrace('EnqueueTCPRequest: New connection to Port %d', 0, LocalPort, 0);{$ENDIF}
end;

// Send a packet using the local Network interface
// It 's an async API , the packet is send when "ready" register is True
procedure SysNetworkSend(Packet: PPacket);
var
  CPUID: LongInt;
  NetworkInterface: PNetworkInterface;
begin
  CPUID := GetApicID;
  NetworkInterface := DedicateNetworks[CPUID].NetworkInterface;
  Packet.Ready := False;
  Packet.Status := False;
  Packet.Next:= nil;
  NetworkInterface.Send(NetworkInterface, Packet);
end;

const
  ARP_OP_REQUEST = 1;
  ARP_OP_REPLY = 2;

// Send an ARP request to translate IP Address ---> Hard Address
// called by: EthernetSendPacket\RouteIP\GetMacAddress
procedure ARPRequest(IpAddress: TIPAddress);
const
  MACBroadcast: THardwareAddress = ($ff,$ff,$ff,$ff,$ff,$ff);
  MACZero: THardwareAddress = (0,0,0,0,0,0);
var
  Packet: PPacket;
  ARPPacket: PArpHeader;
  EthPacket: PEthHeader;
  CpuID: LongInt;
begin
  Packet := ToroGetMem(SizeOf(TPacket)+SizeOf(TArpHeader)+SizeOf(TEthHeader));
  if Packet = nil then
    Exit;
  CPUID:= GetApicid;
  Packet.Data := Pointer(PtrUInt(Packet)+SizeOf(TPacket));
  Packet.Size := SizeOf(TArpHeader)+SizeOf(TEthHeader);
  ARPPacket := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  EthPacket := Packet.Data;
  ARPPacket.Hardware := SwapWORD(1);
  ARPPacket.Protocol := ETH_FRAME_IP;
  ARPPacket.HardwareAddrLength := SizeOf(THardwareAddress);
  ARPPacket.ProtocolAddrLength := SizeOf(TIPAddress);
  ARPPacket.OpCode:= SwapWORD(ARP_OP_REQUEST);
  ARPPacket.TargetHardAddr := MACZero;
  ARPPacket.TargetIpAddr:= IpAddress;
  ARPPacket.SenderHardAddr:= DedicateNetworks[CpuID].NetworkInterface.HardAddress;
  ARPPacket.SenderIPAddr := DedicateNetworks[CpuID].IpAddress;;
  // Sending a broadcast packet
  EthPacket.Destination := MACBroadcast;
  EthPacket.Source:= DedicateNetworks[CpuID].NetworkInterface.HardAddress;
  EthPacket.ProtocolType := SwapWORD(ETH_FRAME_ARP);
  SysNetworkSend(Packet);
  // free the resources
  ToroFreeMem(Packet);
end;


// Return MAC of Local Stack TCP/IP
function GetLocalMAC: THardwareAddress;
begin
  result:= DedicateNetworks[GetApicid].NetworkInterface.HardAddress;
end;

// called by: EthernetSendPacket\RouteIP
function GetMacAddress(IP: TIPAddress): PMachine;
var
  Machine: PMachine;
  I: LongInt;
begin
  //  MAC not in local table -> send ARP request
  I := 3;
  while I > 0 do
  begin
    Machine := LookIp(IP); // MAC already added ?
    if Machine <> nil then
    begin
      Result:= Machine;
      Exit;
    end;
    ARPRequest(IP); // Request the MAC of IP
    Sleep(WAIT_ARP); // Wait for Remote Response
    Dec(I);
  end;
  Result := nil;
end;

// Return a physical Address to correct Destination
// called by: EthernetSendPacket
function RouteIP(IP: TIPAddress) : PMachine;
var
  CPUID: LongInt;
  Net: PNetworkDedicate;
begin
  CPUID:= GetApicid;
  Net := @DedicateNetworks[CPUID];
  if (Net.Mask and IP) <> (Net.Mask and Net.Gateway) then
  begin
    // The Machine is outside , i must use a Gateway
    Result := GetMacAddress(Net.Gateway);
    Exit;
  end;
  // The IP is in the Range i will send directly to the machine
  Result := GetMacAddress(IP);
end;

// Send a packet using low layer ethernet
procedure EthernetSendPacket(Packet: PPacket);
var
  CpuID: LongInt;
  EthHeader: PEthHeader;
  IPHeader: PIPHeader;
  Machine: PMachine;
begin
  CpuID := GetApicid;
  EthHeader := Packet.Data;
  IPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  EthHeader.Source := DedicateNetworks[CpuID].NetworkInterface.HardAddress;
  Machine := RouteIP(IPHeader.destip);
  if Machine = nil then
    Exit;
  EthHeader.Destination := Machine.HardAddress;
  EthHeader.ProtocolType := SwapWORD(ETH_FRAME_IP);
  SysNetworkSend(Packet);
end;

// Make an IP Header for send a IP Packet
procedure IPSendPacket(Packet: PPacket; IpDest: TIPAddress; Protocol: Byte);
var
  IPHeader: PIPHeader;
begin
  IPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  FillChar(IPHeader^, SizeOf(TIPHeader), 0);
  IPHeader.VerLen := IPv4_VERSION_LEN;
  IPHeader.TOS := 0;
  IPHeader.PacketLength := SwapWORD(Packet.Size-SizeOf(TEthHeader));
  Inc(LastId);
  IPHeader.ID := SwapWORD(Word(LastID));
  IPHeader.FragmentOfs := SwapWORD(0);
  IPHeader.ttl := 128;
  IPHeader.Protocol := Protocol;
  IPHeader.SourceIP := DedicateNetworks[GetApicid].IpAddress;
  IPHeader.DestIP := IpDest;
  IPHeader.Checksum := CalculateChecksum(nil,IPHeader,Word(SizeOf(TIPHeader)),0);
  // Send a packet using ethernet layer
  EthernetSendPacket(Packet);
end;

const
 TCPPacketLen : LongInt =  SizeOf(TPacket)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader);

// Uses for System Packets like SYN, ACK or END
procedure TCPSendPacket(Flags: LongInt; Socket: PSocket);
var
  TCPHeader: PTCPHeader;
  Packet: PPacket;
begin
  Packet:= ToroGetMem(TCPPacketLen);
  if Packet = nil then
    Exit;
  Packet.Size := TCPPacketLen - SizeOf(TPacket);
  Packet.Data := Pointer(PtrUInt(Packet) + TCPPacketLen - SizeOf(TPacket));
  Packet.ready := False;
  Packet.Status := False;
  Packet.Delete := True;
  Packet.Next := nil;
  TcpHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
  FillChar(TCPHeader^, SizeOf(TTCPHeader), 0);
  TcpHeader.AckNumber := SwapDWORD(Socket.LastAckNumber);
  TcpHeader.SequenceNumber := SwapDWORD(Socket.LastSequenceNumber);
  TcpHeader.Flags := Flags;
  TcpHeader.Header_Length := (SizeOf(TTCPHeader) div 4) shl 4;
  TcpHeader.SourcePort := SwapWORD(Socket.SourcePort);
  TcpHeader.DestPort := SwapWORD(Socket.DestPort);
  TcpHeader.Window_Size := SwapWORD(MAX_WINDOW - Socket.BufferLength);
  TcpHeader.Checksum := TCP_CheckSum(DedicateNetworks[GetApicid].IpAddress, Socket.DestIp, PChar(TCPHeader), SizeOf(TTCPHeader));
  IPSendPacket(Packet, Socket.DestIp, IP_TYPE_TCP);
  // Sequence Number depends of the flags in the TCP Header
  if (Socket.State = SCK_NEGOTIATION) or (Socket.State = SCK_CONNECTING) or (Socket.State= SCK_LOCALCLOSING) then
    Inc(Socket.LastSequenceNumber)
  else if Socket.State = SCK_TRANSMITTING then
  begin
//    Socket.LastSequenceNumber := Socket.LastSequenceNumber;
  end;
end;

// Inform the Kernel that the last packet has been sent, returns the next packet to send
// Called by ne2000irqhandler.Ne2000Handler
function DequeueOutgoingPacket: PPacket;
var
  CPUID: LongInt;
  Packet: PPacket;
begin
  CPUID := GetApicid;
  Packet := DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets;
  Packet.Ready := True;
  // the packet can be Delete
  if Packet.Delete then
    ToroFreeMem(Packet);
  DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets := Packet.Next;
  DedicateNetworks[CPUID].NetworkInterface.TimeStamp := read_rdtsc;
  Result := DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets;
end;

// Inform to Kernel that a new Packet has been received
// Called by ne2000irqhandler.Ne2000Handler.ReadPacket
procedure EnqueueIncomingPacket(Packet: PPacket);
var
  PacketQueue: PPacket;
begin
  PacketQueue := DedicateNetworks[GetApicId].NetworkInterface.IncomingPackets;
  Packet.Next := nil;
  if PacketQueue = nil then
  begin
    DedicateNetworks[GetApicId].NetworkInterface.IncomingPackets:=Packet;
  end else begin
    // we have packets in the tail
    while PacketQueue.Next <> nil do
      PacketQueue:=PacketQueue.Next;
    PacketQueue.Next := Packet;
  end;
end;

// Port is marked free in Local Socket Bitmap
// Called by FreeSocket
procedure FreePort(LocalPort: LongInt);
var
  CPUID: LongInt;
  Bitmap: Pointer;
begin
  CPUID:= GetApicid;
  Bitmap := @DedicateNetworks[CPUID].SocketStreamBitmap[0];
  Bit_Reset(Bitmap, LocalPort);
end;

// Free all Resources in Socket
// only for Client Sockets
procedure FreeSocket(Socket: PSocket);
var
  ClientSocket: PSocket;
  CPUID: LongInt;
  Service: PNetworkService;
begin
  CPUID:= GetApicID;
  // take the queue of Sockets
  Service := DedicateNetworks[CPUID].SocketStream[Socket.SourcePort];
  // Remove It
  if Service.ClientSocket = Socket then
    Service.ClientSocket := Socket.Next
  else begin
    ClientSocket := Service.ClientSocket;
    while ClientSocket.Next <> Socket do
      ClientSocket := ClientSocket.Next;
    ClientSocket.Next := Socket.Next;
  end;
  // Free port if is necessary
  if Socket.NeedFreePort then
  begin
    if Socket.SocketType = SOCKET_STREAM then
      DedicateNetworks[CPUID].SocketStream[Socket.SourcePort] := nil
    else
      DedicateNetworks[CPUID].SocketDatagram[Socket.SourcePort] := nil;
    FreePort(Socket.SourcePort);
  end;
  // Free Memory Allocated
  ToroFreeMem(Socket.Buffer); // Free the buffer Window
  ToroFreeMem(Socket); // Free Socket Structure
end;

// Processing ARP Packets
procedure ProcessARPPacket(Packet: PPacket);
var
  CPUID: LongInt;
  ArpPacket: PArpHeader;
  EthPacket: PEthHeader;
begin
  CPUID:= GetApicid;
  ArpPacket:=Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  EthPacket:= Packet.Data;
  if SwapWORD(ArpPacket.Protocol) = ETH_FRAME_IP then
  begin
    if ArpPacket.TargetIpAddr=DedicateNetworks[CPUID].IpAddress then
    begin
      // Request of Ip Address
      if ArpPacket.OpCode= SwapWORD(ARP_OP_REQUEST) then
      begin
        EthPacket.Destination:= EthPacket.Source;
        EthPacket.Source:= DedicateNetworks[CPUID].NetworkInterface.HardAddress;
        ArpPacket.OpCode:= SwapWORD(ARP_OP_REPLY);
        ArpPacket.TargetHardAddr:= ArpPacket.SenderHardAddr;
        ArpPacket.TargetIpAddr:= ArpPacket.SenderIpAddr;
        ArpPacket.SenderHardAddr:= DedicateNetworks[CPUID].NetworkInterface.HardAddress;
        ArpPacket.SenderIpAddr:=DedicateNetworks[CPUID].IpAddress;
        SysNetworkSend(Packet);
        // Reply Request of Ip Address
      end else if ArpPacket.OpCode= SwapWORD(ARP_OP_REPLY) then
      begin
        {$IFDEF DebugNetwork} DebugTrace('ProcessARPPacket: New Machine added to Translation Table',0, 0, 0); {$ENDIF}
        // Some problems for Spoofing
        AddTranslateIp(ArpPacket.SenderIPAddr,ArpPacket.SenderHardAddr);
      end;
    end;
  end;
  ToroFreeMem(Packet);
end;

// Check the Socket State and enqueue the packet in correct queue
procedure ProcessTCPSocket(Socket: PSocket; Packet: PPacket);
var
  TCPHeader: PTCPHeader;
  IPHeader: PIPHeader;
  DataSize: UInt32;
  Source, Dest: PByte;
begin
  IPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TETHHeader));
  TCPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TETHHeader)+SizeOf(TIPHeader));
//  DataSize := SwapWord(IPHeader.PacketLength)-SizeOf(TIPHeader)-SizeOf(TTCPHeader);
  case Socket.State of
    SCK_CONNECTING: // The socket is connecting to remote host
      begin
        // It is a valid connection ?
        if (Socket.Mode = MODE_CLIENT) and (TCPHeader.Flags and TCP_SYN = TCP_SYN) then
        begin
          // Is a valid packet?
          if SwapDWORD(TCPHeader.AckNumber)-1 = 300 then
          begin
            // The connection was stablished
            Socket.DispatcherEvent := DISP_CONNECT;
            Socket.LastAckNumber := SwapDWORD(TCPHeader.SequenceNumber)+1;
            Socket.LastSequenceNumber := 301;
            Socket.RemoteWinLen := SwapWORD(TCPHeader.Window_Size);
            Socket.RemoteWinCount :=Socket.RemoteWinLen;
            Socket.State := SCK_TRANSMITTING;
            Socket.BufferLength := 0;
            Socket.Buffer := ToroGetMem(MAX_WINDOW);
            Socket.BufferReader := Socket.Buffer;
            // Confirm the connection sending a ACK
            TCPSendPacket(TCP_ACK, Socket);
          end;
        end;
        ToroFreeMem(Packet);
      end;
    SCK_PEER_DISCONNECTED:
      begin
        // Closing Local Connection
        if TCPHeader.flags and TCP_FIN = TCP_FIN then
        begin
          Socket.LastAckNumber := Socket.LastAckNumber+1;
          // confirm remote close
          TCPSendPacket(TCP_ACK, Socket);
          // Free Resources in Socket
          FreeSocket(Socket);
          {$IFDEF DebugNetwork}DebugTrace('SysSocketClose: Socket Free', 0, 0, 0);{$ENDIF}
        end;
        ToroFreeMem(Packet);
      end;
    SCK_LOCALCLOSING: // The Local user is closing the connection
      begin
        // we have got to wait the REMOTECLOSE
        // we have got to wait a FINACK
        Socket.State := SCK_PEER_DISCONNECTED;
        SetSocketTimeOut(Socket,WAIT_ACKFIN);
        ToroFreeMem(Packet);
      end;
    SCK_BLOCKED: // Server Socket is not listening remote connections
      begin
        ToroFreeMem(Packet)
      end;
    SCK_NEGOTIATION: // Socket is waiting for remote ACK confirmation
      begin
        // the connection has been established
        // The socket starts to receive data , Service Thread has got to do a SysSocketAccept()
        Socket.State := SCK_TRANSMITTING;
        Socket.DispatcherEvent := DISP_ACCEPT;
        ToroFreeMem(Packet);
      end;
    SCK_TRANSMITTING: // Client Socket is connected to remote Host
      begin
      // TODO: we aren't checking if ACK number is correct
       if TCPHeader.flags = TCP_ACK then
       begin
        Socket.LastAckNumber := SwapDWORD(TCPHeader.SequenceNumber);
        // Are we checking zero window condition ?
        if Socket.WinFlag then
        begin
          // The window was refreshed
          //if SwapWord(TCPHeader.Window_Size) <> 0 then
          //  Socket.WinFlag := False;
          Socket.WinFlag := SwapWord(TCPHeader.Window_Size) = 0; // KW 20091204 Reduced previous line of code as suggested by PAL
        end else
        begin
         // Sender Dispatcher is waiting for confirmation
         Socket.AckFlag := True;
         // We have got to block the sender
         if SwapWord(TCPHeader.Window_Size) = 0 then
          Socket.WinFlag := True;
        end;
       end else if TCPHeader.flags = TCP_ACKPSH then
       begin
          if SwapDWORD(TCPHeader.AckNumber) = Socket.LastSequenceNumber then
          begin
            DataSize:= SwapWord(IPHeader.PacketLength)-SizeOf(TIPHeader)-SizeOf(TTCPHeader);
            Socket.LastAckNumber := SwapDWORD(TCPHeader.SequenceNumber)+DataSize;
            Source := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTCPHeader));
            Dest := Pointer(PtrUInt(Socket.Buffer)+Socket.BufferLength);
            Move(Source^, Dest^, DataSize);
            Socket.BufferLength := Socket.BufferLength + DataSize;
            // New Data in buffer!
            // The dispatcher has got to know
            Socket.DispatcherEvent := DISP_RECEIVE;
            //  ACKPSH packet need confirmation
             TCPSendPacket(TCP_ACK, Socket);
          end else begin
            // Invalid Sequence Number
            // sending the correct ACK and Sequence Number
            TCPSendPacket(TCP_ACK, Socket);
          end;
        // END of connection
        end else if (TCPHeader.flags = TCP_ACKEND) then
        begin
          // change the socket State
          Socket.State:= SCK_LOCALCLOSING;
          Socket.DispatcherEvent := DISP_CLOSE;
          TCPSendPacket(TCP_ACK, Socket);
        end;
        ToroFreeMem(Packet)
      end;
  end;
end;

// Validate Request to SERVER Socket
// Called by ProcessNetworksPackets\ProcessIPPacket
function ValidateTCPRequest(IpSrc: TIPAddress; LocalPort, RemotePort: Word): PSocket;
var
  Service: PNetworkService;
  Socket: PSocket;
begin
  Service := DedicateNetworks[GetApicid].SocketStream[LocalPort];
  if Service.ServerSocket = nil then
  begin
    Result := nil;
    Exit;
  end;
    Socket:= Service.ClientSocket;
    // Is it an duplicate connection ?
    while Socket <> nil do
    begin
      if (Socket.DestIP = IPSrc) and (Socket.DestPort = RemotePort) then
      begin
        Result := nil;
        Exit;
    end else
      Socket:= Socket.Next;
    end;
    Result := Service.ServerSocket;
end;

// Manipulation of IP Packets, redirect the traffic to Sockets structures
// Called by ProcessNetworksPackets
procedure ProcessIPPacket(Packet: PPacket);
var
  IPHeader: PIPHeader;
  TCPHeader: PTCPHeader;
  Socket: PSocket;
  ICMPHeader: PICMPHeader;
  EthHeader: PEthHeader;
  DataLen: LongInt;
begin
  IPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader));
  case IPHeader.protocol of
    IP_TYPE_ICMP :
      begin
        ICMPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
        EthHeader := Packet.Data;
        // Request of Ping
        if ICMPHeader.tipe = ICMP_ECHO_REQUEST then
        begin
          Packet.Size := Packet.Size - 4;
          ICMPHeader.tipe:= ICMP_ECHO_REPLY;
          ICMPHeader.checksum :=0 ;
          Datalen:= SwapWORD(IPHeader.PacketLength) - SizeOf(TIPHeader);
          ICMPHeader.Checksum := CalculateChecksum(nil,ICMPHeader,DataLen,0);
          AddTranslateIp(IPHeader.SourceIP,EthHeader.Source); // I'll use a MAC address of Packet
          IPSendPacket(Packet,IPHeader.SourceIP,IP_TYPE_ICMP); // sending response
        end;
        {$IFDEF DebugNetwork} DebugTrace('IPPacketService: Arriving ICMP packet', 0, 0, 0); {$ENDIF}
        ToroFreeMem(Packet);
      end;
    IP_TYPE_UDP  :
      begin
        {$IFDEF DebugNetwork} DebugTrace('IPPacketService: Arriving UDP packet', 0, 0, 0); {$ENDIF}
        ToroFreeMem(Packet);
      end;
    IP_TYPE_TCP  :
      begin
        TCPHeader := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
        {$IFDEF DebugNetwork} DebugTrace('IPPacketService: Arriving TCP packet', 0, 0, 0); {$ENDIF}
        if TCPHeader.Flags=TCP_SYN then
        begin
          // Validate the REQUEST to Server Socket
          Socket:= ValidateTCPRequest(IPHeader.SourceIP,SwapWORD(TCPHeader.DestPort),SwapWORD(TCPHeader.SourcePort));
          // Enqueue the request to socket
          if Socket <> nil then
            EnqueueTCPRequest(Socket, Packet)
          else
            ToroFreeMem(Packet);
          {$IFDEF DebugNetwork} DebugTrace('IPPacketService: SYN Packet arrived', 0, 0, 0); {$ENDIF}
        end else if (TCPHeader.Flags and TCP_ACK = TCP_ACK) then
        begin
          // Validate connection
          Socket:= ValidateTCP(IPHeader.SourceIP,SwapWORD(TCPHeader.SourcePort),SwapWORD(TCPHeader.DestPort));
          {$IFDEF DebugNetwork} DebugTrace('IPPacketService: ACK Packet arrived', 0, 0, 0); {$ENDIF}
          if Socket <> nil then
            ProcessTCPSocket(Socket,Packet)
          else begin
            {$IFDEF DebugNetwork} DebugTrace('IPPacketService: ACK Packet invalid', 0, 0, 0); {$ENDIF}
            ToroFreeMem(Packet);
          end;
          // RST Flags
        end else if (TCPHeader.Flags and TCP_RST = TCP_RST) then
        begin
          Socket:= ValidateTCP(IPHeader.SourceIP,SwapWORD(TCPHeader.SourcePort),SwapWORD(TCPHeader.DestPort));
          // If the conection exist then socket is closed
          // If socket is in connecting to remote host the packet is not important for connection
          if (Socket <> nil) and (Socket.State <> SCK_CONNECTING) then
            Socket.State:= SCK_CLOSED;
          ToroFreeMem(Packet);
        end;
      end;
    else begin
      // Unknow Protocol
      ToroFreeMem(Packet);
    end;
  end;
end;

// Read a packet from Buffer of local Network Interface
// Need to protect call against concurrent access
// Called by ProcessNetworksPackets
function SysNetworkRead: PPacket;
var
  CPUID: LongInt;
  Packet: PPacket;
begin
  CPUID := GetApicID;
  DisabledINT;
  Packet := DedicateNetworks[CPUID].NetworkInterface.IncomingPackets;
  if Packet=nil then
    Result := nil
  else begin
    DedicateNetworks[CPUID].NetworkInterface.IncomingPackets := Packet.Next;
    Result := Packet;
  end;
  EnabledINT;
end;

// Thread function, processing new packets
function ProcessNetworksPackets(Param: Pointer): PtrInt;
var
  Packet: PPacket;
  EthPacket: PEthHeader;
  r: Int64;
  Net: PNetworkInterface;
begin
  Result := 0;
  Net := DedicateNetworks[GetApicid].NetworkInterface;
  while True do
  begin
    // new packet read
    // and new block of memory is allocated if packet <> the nil
    Packet := SysNetworkRead;
    if Packet = nil then
    begin // we have to check if the driver is sending correctly
      if (Net.TimeStamp <> 0) and (Net.OutgoingPackets <> nil) then
      begin
        r := read_rdtsc-Net.TimeStamp;
        // Maybe the driver is in a loop, we have to inform the driver
        if (r > MAX_TIME_SENDER*LocalCPUSpeed*1000) then
          Net.Reset(Net);
      end;
      SysThreadSwitch;
      Continue;
    end;
    EthPacket := Packet.Data;
    case SwapWORD(EthPacket.ProtocolType) of
      ETH_FRAME_ARP:
        begin
        {$IFDEF DebugNetwork} DebugTrace('EthernetPacketService: Arriving ARP packet', 0, 0, 0); {$ENDIF}
          ProcessARPPacket(Packet);
        end;
      ETH_FRAME_IP:
        begin
          {$IFDEF DebugNetwork} DebugTrace('EthernetPacketService: Arriving IP packet', 0, 0, 0); {$ENDIF}
          ProcessIPPacket(Packet);
        end;
    else
      begin
        {$IFDEF DebugNetwork} DebugTrace('EthernetPacketService: Arriving unknow packet', 0, 0, 0); {$ENDIF}
        ToroFreeMem(Packet);
      end;
    end;
  end;
end;

// Initilization of threads running like services on current CPU
procedure NetworkServicesInit;
var
  ThreadID: TThreadID;
begin
  if PtrUInt(BeginThread(nil, 10*1024, @ProcessNetworksPackets, nil, DWORD(-1), ThreadID)) <> 0 then
    printk_('Networks Packets Service .... /VRunning/n\n',0)
  else
    printk_('Networks Packets Service .... /VFail!/n\n',0);
end;

// Initialize the dedicated network interface
function LocalNetworkInit: Boolean;
var
  CPUID, I: LongInt;
begin
  CPUID:= GetApicID;
  // cleaning table
  DedicateNetworks[CPUID].NetworkInterface.OutgoingPackets := nil;
  DedicateNetworks[CPUID].NetworkInterface.IncomingPackets := nil;
  // Initilization of Services for Packets Manipulation
  NetworkServicesInit;
  // Driver internal initilization
  DedicateNetworks[CPUID].NetworkInterface.start(DedicateNetworks[CPUID].NetworkInterface);
  // cleaning the Socket table
  for I:= 0 to (MAX_SocketPORTS-1) do
  begin
    DedicateNetworks[CPUID].SocketStream[I]:=nil;
    DedicateNetworks[CPUID].SocketDatagram[I]:=nil;
  end;
  // the drivers is sending and receiving packets
  Result:= True;
end;

// Dedicate the Network Interface to CPU in CPUID
// If Handler=nil then the Network Stack is managed by the KERNEL
procedure DedicateNetwork(const Name: AnsiString; const IP, Gateway, Mask: array of Byte; Handler: TThreadFunc);
var
  CPUID: LongInt;
  Net: PNetworkInterface;
  Network: PNetworkDedicate;
  ThreadID: TThreadID;
begin
  Net := NetworkInterfaces;
  CPUID := GetApicid;
  while Net <> nil do
  begin
    if (Net.Name = Name) and (Net.CPUID = -1) and (DedicateNetworks[CPUID].NetworkInterface = nil) then
    begin
      // Only this CPU will be granted access to this network interface
      Net.CPUID := CPUID;
      DedicateNetworks[CPUID].NetworkInterface := Net;
      // The User Hands the packets
      if @Handler <> nil then
      begin
        if PtrUInt(BeginThread(nil, 10*1024, @Handler, nil, DWORD(-1), ThreadID)) <> 0 then
          printk_('Network Packets Service .... /VRunning/n\n',0)
        else
        begin
          printk_('Network Packets Service .... /VFail!/n\n',0);
          exit;
        end;
      end else
      begin // Initialize Local Packet-Cache, the kernel will handle packets
        if not LocalNetworkInit then
        begin
          DedicateNetworks[CPUID].NetworkInterface := nil;
          Exit;
        end;
      end;
      // Loading the IP address
      // some translation from array of Byte to LongInt
      Network := @DedicateNetworks[CPUID];
      _IPAddress(IP, Network.IpAddress);
      _IPAddress(Gateway, Network.Gateway);
      _IPAddress(Mask, Network.Mask);
      printk_('Network configuration :\n',0);
      printk_('Local IP ... /V%d.', Network.Ipaddress and $ff);
      printk_('%d.', (Network.Ipaddress shr 8) and $ff);
      printk_('%d.', (Network.Ipaddress shr 16) and $ff);
      printk_('%d\n', (Network.Ipaddress shr 24) and $ff);
      printk_('/nGateway ...  /V%d.', Network.Gateway and $ff);
      printk_('%d.', (Network.Gateway shr 8) and $ff);
      printk_('%d.', (Network.Gateway shr 16) and $ff);
      printk_('%d\n', (Network.Gateway shr 24) and $ff);
      printk_('/nMask ...  /V%d.', Network.Mask and $ff);
      printk_('%d.', (Network.Mask shr 8) and $ff);
      printk_('%d.', (Network.Mask shr 16) and $ff);
      printk_('%d\n/n', (Network.Mask shr 24) and $ff);
      {$IFDEF DebugNetwork} DebugTrace('DedicateNetwork: New Driver dedicate to CPU#%d',0,CPUID,0); {$ENDIF}
      Exit;
    end;
    Net := Net.Next;
  end;
end;

// Initilization of Network structures
procedure NetworkInit;
var
  I: LongInt;
begin
  printK_('Network Tcp-Ip Stack ... /VOk!/n\n',0);
  // Clean tables
  for I := 0 to (MAX_CPU-1) do
  begin
    DedicateNetworks[I].NetworkInterface := nil;
    DedicateNetworks[I].TranslationTable := nil;
    // Free all ports
    FillChar(DedicateNetworks[I].SocketStreamBitmap, SZ_SocketBitmap, 0);
    FillChar(DedicateNetworks[I].SocketDatagram, MAX_SocketPORTS*SizeOf(Pointer), 0);
    FillChar(DedicateNetworks[I].SocketStream, MAX_SocketPORTS*SizeOf(Pointer), 0);
  end;
  NetworkInterfaces := nil;
end;



//------------------------------------------------------------------------------
// Socket Implementation
//------------------------------------------------------------------------------

// Return True if the Timer expired
function CheckTimeOut(Counter, TimeOut: Int64): Boolean;
var
  ResumeTime: Int64;
begin
  ResumeTime := read_rdtsc;
  // Correction for Overflow
  if Counter < ResumeTime then
    Counter := Counter - ResumeTime
  else
    Counter := $FFFFFFFF-Counter+ResumeTime;
  if TimeOut < Counter then
    Result := True
  else
    Result := False;
end;

// Send the packets prepared in Buffer
procedure DispatcherFlushPacket(Socket: PSocket);
var
  Buffer: PBufferSender;
  DataLen: UInt32;
begin
  // Sender Dispatcher can't send  , we have got to wait for remote host
  // While The WinFlag is up the timer 'll be refreshed
  if not Socket.AckFlag and Socket.WinFlag then
  begin
    if CheckTimeOut(Socket.WinCounter, Socket.WinTimeOut) then
    begin
      // we have got to check if the remote window was refreshed
      TCPSendPacket(TCP_ACK, Socket);
      // Set the timer again
      Socket.WinCounter := read_rdtsc;
      Socket.WinTimeOut := WAIT_WIN*LocalCPUSpeed*1000;
    end;
    Exit;
  end;
  // the socket doesn't have packets to send
  if Socket.BufferSender = nil then
    Exit;
  // we are waiting for a complete an operation ?
  if Socket.AckTimeOUT <> 0 then
  begin
    Buffer := Socket.BufferSender;
    if Socket.AckFlag then
    begin // the packet has been sent correctly
      Socket.AckFlag := False; // clear the flag
      Socket.AckTimeOut:= 0;
      DataLen := Buffer.Packet.Size - (SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader));
      Buffer := Socket.BufferSender.NextBuffer;
      ToroFreeMem(Socket.BufferSender.Packet); // Free the packet
      ToroFreeMem(Socket.BufferSender); // Free the Buffer
      Socket.LastSequenceNumber := Socket.LastSequenceNumber+DataLen;
      // preparing the next packet to send
      Socket.BufferSender := Buffer;
      if Socket.WinFlag then
      begin
        Socket.WinCounter := read_rdtsc;
        Socket.WinTimeOut := WAIT_WIN*LocalCPUSpeed*1000;
        Exit;
      end;
      if Buffer = nil then
        Exit; // no more packet
    end else
    begin
      // TimeOut expired ?
      if not CheckTimeOut(Socket.BufferSender.Counter,Socket.AckTimeOut) then
        Exit;
      // Hardware problem !!!
      // we need to re-calculate the RDTSC register counter
      // the timer will be recalculated until the packet has been sent
      // The packet is still queued in Network Buffer
      if not(Socket.BufferSender.Packet.Ready) then
      begin
        Socket.BufferSender.Counter := read_rdtsc;
        Exit;
      end;
      // number of attemps
      if Buffer.Attempts = 0 then
      begin
        // We lost the connection
        Socket.State := SCK_BLOCKED ;
        Socket.AckTimeOut := 0;
        // We have got to CLOSE
        Socket.DispatcherEvent := DISP_CLOSE ;
      end else
        Dec(Buffer.Attempts);
    end;
  end;
  Socket.ACKFlag := False;
  Socket.AckTimeOut := WAIT_ACK*LocalCPUSpeed*1000;
  Socket.BufferSender.Counter := read_rdtsc;
  IPSendPacket(Socket.BufferSender.Packet, Socket.DestIp, IP_TYPE_TCP);
end;

// Dispatch every ready Socket to its associated Network Service
procedure NetworkDispatcher(Handler: PNetworkHandler);
var
  CountTime: Int64;
  NextSocket: PSocket;
  ResumeTime: Int64;
  Service: PNetworkService;
  Socket: PSocket;
begin
  Service := GetCurrentThread.NetworkService; // Get Network Service structure
  NextSocket := Service.ClientSocket; // Get Client queue
  Socket := NextSocket;
  // we will execute a handler for every socket depending of the EVENT
  while NextSocket <> nil do
  begin
    NextSocket := Socket.Next;
    case Socket.DispatcherEvent of
      DISP_ACCEPT :
        begin // new connection
          Handler.DoAccept(Socket);
        end;
      DISP_WAITING:
        begin // The sockets is waiting for an external event
          ResumeTime:= read_rdtsc;
          // Correction for Overflow
          if Socket.Counter < ResumeTime then
            CountTime:= Socket.Counter - ResumeTime
          else
            CountTime:= $ffffffff-Socket.Counter+ResumeTime;
          // the TimeOut has expired
          if Socket.TimeOut < CountTime then
          begin
            // if client connection lost, need to reconnect
            // In ConnectFail event, need to call connect()
            if Socket.State = SCK_CONNECTING then
            begin
              Socket.State := SCK_BLOCKED;
              Handler.DoConnectFail(Socket)
            end  else if Socket.State = SCK_LOCALCLOSING then
            begin
              // we lost the connection, free the socket
              FreeSocket(Socket)
            end else if Socket.State = SCK_PEER_DISCONNECTED then
            begin
              // ACKFIN never received
              FreeSocket(Socket)
            end else if Socket.State = SCK_NEGOTIATION then
            begin
              // The ACK never came  , we 'll close the connection
              FreeSocket(Socket);
            end else
            begin
              Socket.DispatcherEvent := DISP_TIMEOUT;
              Handler.DoTimeOut(Socket)
            end
          end;
        end;
      DISP_RECEIVE: Handler.DoReceive(Socket); // Has the socket new data?
      DISP_CLOSE: Handler.DoClose(Socket); // Peer socket disconnected
      DISP_CONNECT: Handler.DoConnect(Socket);
    end;
    DispatcherFlushPacket(Socket); // Send the packets in the buffer
    Socket := NextSocket;
  end;
end;

// Do all internal job of service
function DoNetworkService(Handler: PNetworkHandler): LongInt;
begin
  Handler.DoInit; // Initilization of Service
  while True do
  begin
    NetworkDispatcher(Handler); // Fetch event for socket and dispatch
    SysThreadSwitch;
  end;
  Result := 0;
end;

// Register a Network service, this is a system thread
procedure SysRegisterNetworkService(Handler: PNetworkHandler);
var
  Service: PNetworkService;
  Thread: PThread;
  ThreadID: TThreadID; // FPC was using ThreadVar ThreadID
begin
  Service:= ToroGetMem(SizeOf(TNetworkService));
  if Service = nil then
    Exit;
  // Create a Thread to make the job of service, it is created on LOCAL CPU
  ThreadID := BeginThread(nil, 10*1024, @DoNetworkService, Handler, DWORD(-1), ThreadID);
  Thread := Pointer(ThreadID);
  if Thread = nil then
  begin
    ToroFreeMem(Service);
    Exit;
  end;
  // Enqueue the Service Network structure
  Thread.NetworkService := Service;
  Service.ServerSocket := nil;
  Service.ClientSocket := nil;
end;

// Return a Pointer to a new Socket
function SysSocket(SocketType: LongInt): PSocket;
var
  Socket: PSocket;
begin
  Socket := ToroGetMem(SizeOf(TSocket));
  if Socket = nil then
  begin
    Result := nil;
    Exit;
  end;
  // It doesn't need dispatch at the moment
  Socket.DispatcherEvent := DISP_ZOMBIE;
  Socket.State := 0;
  Socket.SocketType := SocketType;
  Socket.BufferLength:= 0;
  Socket.Buffer:= nil;
  Socket.AckFlag := False;
  Socket.AckTimeOut := 0;
  Socket.BufferSender := nil;
  FillChar(Socket.DestIP, 0, SizeOf(TIPAddress));
  Socket.DestPort := 0 ;
  Result := Socket;
  {$IFDEF DebugNetwork} DebugTrace('SysSocket: New Socket Type %d', 0, SocketType, 0); {$ENDIF}
end;

// Configure the Socket , this is call is not necesary because the user has access to Socket Structure
// is implemented only for compatibility. IpLocal is ignored
function SysSocketBind(Socket: PSocket; IPLocal, IPRemote: TIPAddress; LocalPort: LongInt): Boolean;
begin
  Socket.SourcePort := LocalPort;
  Socket.DestIP := IPRemote;
  Result := True;
end;



// Return a free port from Local Socket Bitmap
function GetFreePort:LongInt;
var
  CPUID, J: LongInt;
  Bitmap: Pointer;
begin
  CPUID:= GetApicid;
  Bitmap := @DedicateNetworks[CPUID].SocketStreamBitmap[0];
  // looking for free ports in Bitmap
  for J:= 0 to MAX_SocketPorts-USER_START_PORT do
  begin
    if not Bit_Test(bitmap,J) then
    begin
      Bit_Set(bitmap,J);
      Result := J + USER_START_PORT;
      Exit;
    end;
  end;
  // We don't have free ports
  Result := USER_START_PORT-1;
end;

// Connect to Remote HOST
function SysSocketConnect(Socket: PSocket): Boolean;
var
  CPUID: LongInt;
  Service: PNetworkService;
begin
  CPUID:= GetApicid;
  Socket.Buffer := ToroGetMem(MAX_WINDOW);
  // we haven't got memory
  if Socket.Buffer = nil then
  begin
    Result:=False;
    Exit;
  end;
  Socket.SourcePort := GetFreePort;
  // we haven't got free ports
  if Socket.SourcePort < USER_START_PORT then
  begin
    ToroFreeMem(Socket.Buffer);
    Socket.SourcePort:= 0 ;
    Result := False;
    Exit;
  end;
  // Configure Client Socket
  Socket.State := SCK_CONNECTING;
  Socket.mode := MODE_CLIENT;
  Socket.NeedFreePort := True;
  Socket.BufferLength := 0;
  Socket.BufferLength:=0;
  Socket.BufferReader:= Socket.Buffer;
  // Enqueue the Thread Service structure to array of ports
  Service := GetCurrentThread.NetworkService;
  DedicateNetworks[CPUID].SocketStream[Socket.SourcePort]:= Service ;
  // Enqueue the socket
  Socket.Next := Service.ClientSocket;
  Service.ClientSocket := Socket;
  {$IFDEF DebugNetwork} DebugTrace('SysSocketConnect: Connecting from Port %d to Port %d', 0, Socket.SourcePort, Socket.DestPort); {$ENDIF}
  // SYN is sended , request of connection
  Socket.LastAckNumber := 0;
  Socket.LastSequenceNumber := 300;
  TcpSendPacket(TCP_SYN, Socket);
  // we have got to set a TimeOut for wait the ACK confirmation
  SetSocketTimeOut(Socket,WAIT_ACK);
  Result := True;
end;

// Close connection to Remote Host
// Just for Client Sockets
procedure SysSocketClose(Socket: PSocket);
begin
  {$IFDEF DebugNetwork} DebugTrace('SysSocketClose: Closing Socket in port %d', 0, Socket.SourcePort, 0); {$ENDIF}
  // The connection has been closed from Remote Machine
  if Socket.State = SCK_LOCALCLOSING then
  begin
    Socket.State := SCK_PEER_DISCONNECTED;
    // Close Local Connecton
    TCPSendPacket(TCP_ACK OR TCP_FIN,Socket);
    // We have got to set a TimeOut for wait the ACK
    SetSocketTimeOut(Socket,WAIT_ACK);
    Exit;
  end;
  // we have got to wait the ACK of remote host
  Socket.State := SCK_LOCALCLOSING;
  SetSocketTimeOut(Socket, WAIT_ACK);
  // Send ACKFIN to remote host
  TCPSendPacket(TCP_ACK or TCP_FIN, Socket);
  // in Remote Closing the local host wait for remote ACKFIN
  {$IFDEF DebugNetwork} DebugTrace('SysSocketClose: Socket %d in LocalClosing State', 0, Socket.SourcePort, 0); {$ENDIF}
end;

// Prepare the Socket for receive connections , the socket is in BLOCKED State
function SysSocketListen(Socket: PSocket; QueueLen: LongInt): Boolean;
var
  CPUID: LongInt;
  Service: PNetworkService;
begin
  CPUID := GetApicid;
  Result := False;
  // SysSocketListen() is only for TCP.
  if Socket.SocketType <> SOCKET_STREAM then
    Exit;
  // Listening port always are above to USER_START_PORT
  if Socket.SourcePORT >= USER_START_PORT then
    Exit;
  Service := DedicateNetworks[CPUID].SocketStream[Socket.SourcePort];
  // The port is busy
  if (Service <> nil) then
   Exit;
  // Enqueue the Server Socket to Thread Network Service structure
  Service:= GetCurrentThread.NetworkService;
  Service.ServerSocket := Socket;
  DedicateNetworks[CPUID].SocketStream[Socket.SourcePort]:= Service;
 // socket is waiting for new connections
  Socket.State := SCK_LISTENING;
  Socket.Mode := MODE_SERVER;
  Socket.NeedfreePort := False;
  // Max Number of remote conenctions pendings
  Socket.ConnectionsQueueLen := QueueLen;
  Socket.ConnectionsQueueCount := 0;
  Socket.DestPort:=0;
  Result := True;
  {$IFDEF DebugNetwork} DebugTrace('SysSocketListen: Socket installed in Local Port: %d', 0, Socket.SourcePort, 0); {$ENDIF}
end;

// Read Data from Buffer and save it in Addr , The data continue into the buffer
function SysSocketPeek(Socket: PSocket; Addr: PChar; AddrLen: UInt32): LongInt;
var
  FragLen: LongInt;
begin
  {$IFDEF DebugNetwork} DebugTrace('SysSocketPeek BufferLength: %d', 0, Socket.BufferLength, 0); {$ENDIF}
  {$IFDEF DebugNetwork} DebugTrace(PXChar(Socket.Buffer), 0, 0, 0); {$ENDIF}
  Result := 0;
  if (Socket.State <> SCK_TRANSMITTING) or (AddrLen=0) or (Socket.Buffer+Socket.BufferLength=Socket.BufferReader) then
  begin
    {$IFDEF DebugNetwork} DebugTrace('SysSocketPeek -> Exit', 0, 0, 0); {$ENDIF}
    Exit;
  end;
  while (AddrLen > 0) and (Socket.State = SCK_TRANSMITTING) do
  begin
    if Socket.BufferLength > AddrLen then
    begin
      FragLen := AddrLen;
      AddrLen := 0;
    end else begin
      FragLen := Socket.BufferLength;
      AddrLen := 0;
    end;
    Move(Socket.BufferReader^, Addr^, FragLen);
    {$IFDEF DebugNetwork} DebugTrace('SysSocketPeek:  %q bytes from port %d to port %d ', PtrUint(FragLen), Socket.SourcePort, Socket.DestPort); {$ENDIF}
    Result := Result + FragLen;
  end;
end;

// Read Data from Buffer and save it in Addr
function SysSocketRecv(Socket: PSocket; Addr: PChar; AddrLen, Flags: UInt32): LongInt;
var
  FragLen: LongInt;
begin
  {$IFDEF DebugNetwork} DebugTrace('SysSocketRecv BufferLength: %d', 0, Socket.BufferLength, 0); {$ENDIF}
  {$IFDEF DebugNetwork} DebugTrace(PXChar(Socket.Buffer), 0, 0, 0); {$ENDIF}
  Result := 0;
  if (Socket.State <> SCK_TRANSMITTING) or (AddrLen=0) or (Socket.Buffer+Socket.BufferLength = Socket.BufferReader) then
  begin
    {$IFDEF DebugNetwork} DebugTrace('SysSocketRecv -> Exit', 0, 0, 0); {$ENDIF}
    Exit;
  end;
  while (AddrLen > 0) and (Socket.State = SCK_TRANSMITTING) do
  begin
    if Socket.BufferLength > AddrLen then
    begin
      FragLen := AddrLen;
      AddrLen := 0;
    end else begin
      FragLen := Socket.BufferLength;
      AddrLen := 0;
    end;
    Move(Socket.BufferReader^, Addr^, FragLen);
    {$IFDEF DebugNetwork} DebugTrace('SysSocketRecv: Receiving %q bytes from port %d to port %d ', PtrUint(FragLen), Socket.SourcePort, Socket.DestPort); {$ENDIF}
    Result := Result + FragLen;
    Socket.BufferReader := Socket.BufferReader + FragLen;
    // The buffer was readed , inform to sender that it can send data again
    if Socket.BufferReader = (Socket.Buffer+MAX_WINDOW) then
    begin
      {$IFDEF DebugNetwork} DebugTrace('SysSocketRecv: TCPSendPacket TCP_ACK', 0, 0, 0); {$ENDIF}
      Socket.BufferReader := Socket.Buffer;
      Socket.BufferLength := 0;
    end;
  end;
end;

// The Socket waits for notification, and returns when a new event is received
// External events are REMOTECLOSE, RECEIVE or TIMEOUT
// API reserved for Socket Client, should be called from event handler
function SysSocketSelect(Socket: PSocket; TimeOut: LongInt): Boolean;
begin
  Result:=True;
  // The socket has a remote closing
  if Socket.State = SCK_LOCALCLOSING then
  begin
    Socket.DispatcherEvent := DISP_CLOSE;
    Exit;
  end;
  // We have data in a Reader Buffer ?
  if Socket.BufferReader < Socket.Buffer+Socket.BufferLength then
  begin
    Socket.DispatcherEvent := DISP_RECEIVE;
    Exit;
  end;
  // Set a TIMEOUT for wait a remote event
  SetSocketTimeOut(Socket, TimeOut);
end;

// Send data to Remote Host using a Client Socket
// every packet is sended with ACKPSH bit  , with the maximus size  possible.
function SysSocketSend(Socket: PSocket; Addr: PChar; AddrLen, Flags: UInt32): LongInt;
var
  Buffer: PBufferSender;
  Dest: PByte;
  FragLen: UInt32;
  P: PChar;
  Packet: PPacket;
  TCPHeader: PTCPHeader;
  TempBuffer: PBufferSender;
begin
  P := Addr;
  Result := AddrLen;
  while (Addrlen>0) do
  begin
    // every packet has FragLen bytes
    if Addrlen > MTU then
      FragLen:= MTU
    else
      FragLen:= Addrlen;
    // we can only send if the remote host can receiv
    if Fraglen > Socket.RemoteWinCount then
      Fraglen := Socket.RemoteWinCount;
    Socket.RemoteWinCount := Socket.RemoteWinCount - Fraglen; // Decrement Remote Window Size
    // Refresh the remote window size
    if Socket.RemoteWinCount = 0 then
      Socket.RemoteWinCount:= Socket.RemoteWinLen ;
    // we need a new packet
    Packet := ToroGetMem(SizeOf(TPacket)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader)+FragLen);
    // we need a new packet structure
    Buffer := ToroGetMem(SizeOf(TBufferSender));
    // TODO: Maybe the syscall returns nil
    Packet.Data := Pointer(PtrUInt(Packet) + SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader));
    Packet.Size := SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader)+FragLen;
    Packet.ready := False;
    Packet.Delete := False;
    Packet.Next := nil;
    // Fill TCP paramters
    TcpHeader:= Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader));
    FillChar(TCPHeader^, SizeOf(TTCPHeader), 0);
    // Copy user DATA to new packet
    Dest := Pointer(PtrUInt(Packet.Data)+SizeOf(TEthHeader)+SizeOf(TIPHeader)+SizeOf(TTcpHeader));
    Move(P^, Dest^, FragLen);
    TcpHeader.AckNumber := SwapDWORD(Socket.LastAckNumber);
    TcpHeader.SequenceNumber := SwapDWORD(Socket.LastSequenceNumber);
    TcpHeader.Flags := TCP_ACKPSH;
    TcpHeader.Header_Length := (SizeOf(TTCPHeader) div 4) shl 4;
    TcpHeader.SourcePort := SwapWORD(Socket.SourcePort);
    TcpHeader.DestPort := SwapWORD(Socket.DestPort);
    // Local Window Size
    TcpHeader.Window_Size := SwapWORD(MAX_WINDOW - Socket.BufferLength);
    TcpHeader.Checksum := TCP_CheckSum(DedicateNetworks[GetApicid].IpAddress, Socket.DestIp, PChar(TCPHeader), FragLen+SizeOf(TTCPHeader));
    // Buffer Sender structure, the dispatcher works with that structure
    Buffer.Packet := Packet;
    Buffer.NextBuffer := nil;
    Buffer.Attempts := 2;
    // Enqueue Buffer
    if Socket.BufferSender = nil then
      Socket.BufferSender := Buffer
    else
    begin
      TempBuffer := Socket.BufferSender;
      while TempBuffer.NextBuffer <> nil do
        TempBuffer := TempBuffer.NextBuffer;
      TempBuffer.NextBuffer := Buffer;
    end;
    // Next data to send
    AddrLen := Addrlen - FragLen;
    P := P+FragLen;
  end;
end;

end.


