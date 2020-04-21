module TASM_86 where

  import Data.Char
  import Data.List
  import Data.List.Extra

  import AST
  import ThreeAddressCode

  data Register             = BP
                              | EBP
                              | IP
                              | SP
                              | ESP
                              | DI
                              | SI
                              | CS
                              | DS
                              | ES
                              | FS
                              | GS
                              -- General purpose registers
                              | EAX
                              | AX
                              | AL
                              | AH
                              | EBX
                              | BX
                              | BL
                              | BH
                              | ECX
                              | CX
                              | CL
                              | CH
                              | EDX
                              | DX
                              | DL
                              | DH
                              deriving (Show, Eq)

  data Arg                  =  Literal Integer
                              | LiteralWithString String
                              | Register Register
                              | Parameter Integer
                              | Indirect Integer Register
                              deriving (Show, Eq)

  data SizeEnum             = SizeByte
                              | SizeWord
                              | SizeDoubleWord
                              deriving (Show, Eq)

  data ModelSizeEnum        = ModelSizeSmall
                              deriving (Show, Eq)

  data Segment              = CodeSegment
                              | DataSegment
                              | StackSegment
                              deriving (Show, Eq)

  data Label                = LabelString String
                              | LabelId Integer
                              deriving (Show, Eq)

  data Style                = Flat
                              | Text
                              deriving (Show, Eq)
  data Assumption           = Assumption Register Style
                              deriving (Show, Eq)

  data Operation            = MovOp Arg Arg SizeEnum
                              | PushOp Arg SizeEnum
                              | PopOp Arg
                              | CallOp FunctionName
                              | EndprocOp FunctionName
                              | StartprocOp FunctionName
                              | LblOp Label
                              | JmpOp Label
                              -- | ArgOp Integer SizeEnum -- discontinued
                              | AddOp Arg Arg
                              | SubOp Arg Arg
                              | XorOp Arg Arg
                              | CmpOp Arg Arg
                              | DivOp Arg
                              | IncOp Arg
                              | DecOp Arg
                              | JnzOp Label
                              | RetOp
                              | IntOp Arg -- Interrupt
                              | StiOp -- set The Interrupt Flag => enable interrupts
                              | CldOp -- clear The Direction Flag
                              | PopAd
                              | PushAd
                              -- Directives
                              | Ideal
                              | P386
                              | ModelFlatC -- TODO Split this up
                              | Assume [Assumption]
                              | StartSegment Segment
                              | End FunctionName
                              | Empty -- In case you want to add a newline, or a line consisting of only a comment
                              deriving (Show, Eq)
  type Operations           = [Operation]

  bp :: Arg
  bp = Register BP
  ebp :: Arg
  ebp = Register EBP
  sp :: Arg
  sp = Register SP
  esp :: Arg
  esp = Register ESP

  eax :: Arg
  eax = Register EAX
  ax :: Arg
  ax = Register AX
  ah :: Arg
  ah = Register AH
  al :: Arg
  al = Register AL
  ebx :: Arg
  ebx = Register EBX
  bx :: Arg
  bx = Register BX
  ecx :: Arg
  ecx = Register ECX
  cx :: Arg
  cx = Register CX
  edx :: Arg
  edx = Register EDX
  dx :: Arg
  dx = Register DX

  retReg :: Arg -- The register where a function's return value will be placed in
  retReg = eax