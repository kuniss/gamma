module epsilon.sleaggen;

import core.time : MonoTime;
import EAG = epsilon.eag;
import epsilon.settings;
import io : Input, Position, read;
import log;
import runtime;
import std.bitmanip : BitArray;
import std.stdio;
import std.typecons;

public const parsePass = 0;
public const onePass = 1;
public const sSweepPass = 2;
public int[] NodeIdent;
public int[] Leaf;
public int[] AffixPlace;
public int[] AffixSpace;

private File Mod;
private bool SavePos;
private bool UseConst;
private bool UseRefCnt;
private bool TraversePass;
private int[] VarCnt;
private int[] VarAppls;
private bool Testing;
private bool Generating;
private BitArray PreparedHNonts;
private int[] VarDeps;
private int FirstHeap;
private int MaxMAlt;
private long RefConst;
private int[] AffixName;
private BitArray HNontDef;
private int[] HNontVars;
private int[] HNontFVars;
private bool[] RepAppls;
private int[] FormalName;
private int[] VarRefCnt;
private int[] VarDepPos;
private int[] VarName;
private int[] NodeName;
private int IfLevel;
private int[] ActualName;
private BitArray RepVar;
private BitArray EmptySet;

public void Test()
in (EAG.Performed(EAG.analysed | EAG.predicates))
{
    bool isSLEAG;
    bool isLEAG;

    info!"SLEAG testing %s"(EAG.BaseName);
    EAG.History &= ~EAG.isSLEAG;
    InitTest;
    scope (exit)
        FinitTest;
    isSLEAG = true;
    isLEAG = true;
    foreach (N; EAG.Prod.bitsSet)
    {
        if (isSLEAG && EAG.HNont[N].Id >= 0)
        {
            if (!TestHNont(N, true, true))
            {
                isSLEAG = false;
                if (!TestHNont(N, false, false))
                    isLEAG = false;
            }
        }
    }
    if (isSLEAG)
    {
        EAG.History |= EAG.isSLEAG;
        info!"OK";
    }
    else if (isLEAG)
    {
        info!"no SLEAG but LEAG";
    }
    else
    {
        info!"no LEAG";
    }
}

public void InitTest() nothrow
{
    if (!Generating && !Testing)
        PrepareInit;
    Testing = true;
}

public void FinitTest() nothrow
{
    if (!Generating)
        PrepareFinit;
    Testing = false;
}

public bool PredsOK()
{
    bool OK = true;

    foreach (N; EAG.Pred.bitsSet)
        OK = IsLEAG(N, Yes.EmitErr) && OK;
    return OK;
}

public bool IsLEAG(size_t N, bool EmitErr)
{
    return TestHNont(N, EmitErr, false);
}

private bool TestHNont(size_t N, bool EmitErr, bool SLEAG)
{
    EAG.Rule Node;
    EAG.Alt A;
    EAG.Factor F;
    bool isSLEAG;
    bool isLEAG;
    int V;

    void Error(Position Pos, string Msg)
    {
        isSLEAG = false;
        if (EmitErr)
            error!"%s\n%s"(Msg, Pos);
    }

    void CheckDefPos(int P)
    {
        void DefPos(int Node)
        {
            int n;
            int V;
            if (Node < 0)
            {
                V = -Node;
                if (!EAG.Var[V].Def)
                    EAG.Var[V].Def = true;
            }
            else
            {
                for (n = 1; n <= EAG.MAlt[EAG.NodeBuf[Node]].Arity; ++n)
                    DefPos(EAG.NodeBuf[Node + n]);
            }
        }

        while (EAG.ParamBuf[P].Affixform != EAG.nil)
        {
            if (EAG.ParamBuf[P].isDef)
                DefPos(EAG.ParamBuf[P].Affixform);
            ++P;
        }
    }

    void CheckApplPos(int P)
    {
        void ApplPos(int Node)
        {
            int V;

            if (Node < 0)
            {
                V = -Node;
                if (!EAG.Var[V].Def)
                {
                    Error(EAG.Var[V].Pos, "not left-defining");
                    isLEAG = false;
                }
            }
            else
            {
                for (int n = 1; n <= EAG.MAlt[EAG.NodeBuf[Node]].Arity; ++n)
                    ApplPos(EAG.NodeBuf[Node + n]);
            }
        }

        while (EAG.ParamBuf[P].Affixform != EAG.nil)
        {
            if (!EAG.ParamBuf[P].isDef)
                ApplPos(EAG.ParamBuf[P].Affixform);
            ++P;
        }
    }

    void CheckSLEAGCond(int P)
    {
        while (EAG.ParamBuf[P].Affixform != EAG.nil)
        {
            const Node = EAG.ParamBuf[P].Affixform;

            if (EAG.ParamBuf[P].isDef)
            {
                if (Node >= 0)
                    Error(EAG.ParamBuf[P].Pos, "Can't generate anal-predicate here");
                else if (EAG.Var[-Node].Def)
                    Error(EAG.ParamBuf[P].Pos, "Can't generate equal-predicate here");
                else if (EAG.Var[EAG.Var[-Node].Neg].Def)
                    Error(EAG.ParamBuf[P].Pos, "Can't generate unequal-predicate here");
                else if (VarAppls[-Node] > 1)
                    Error(EAG.ParamBuf[P].Pos, "Can't synthesize this variable several times");
            }
            ++P;
        }
    }

    assert(EAG.Prod[N]);

    isSLEAG = true;
    isLEAG = true;
    Prepare(N);
    Node = EAG.HNont[N].Def;
    if (cast(EAG.Rep) Node !is null)
    {
        InitScope((cast(EAG.Rep) Node).Scope);
        CheckDefPos((cast(EAG.Rep) Node).Formal.Params);
        CheckApplPos((cast(EAG.Rep) Node).Formal.Params);
    }
    else if (cast(EAG.Opt) Node !is null)
    {
        InitScope((cast(EAG.Opt) Node).Scope);
        CheckDefPos((cast(EAG.Opt) Node).Formal.Params);
        CheckApplPos((cast(EAG.Opt) Node).Formal.Params);
    }
    A = Node.Sub;
    do
    {
        InitScope(A.Scope);
        CheckDefPos(A.Formal.Params);
        F = A.Sub;
        while (F !is null)
        {
            if (cast(EAG.Nont) F !is null)
            {
                CheckApplPos((cast(EAG.Nont) F).Actual.Params);
                if (SLEAG && EAG.HNont[(cast(EAG.Nont) F).Sym].anonymous)
                    isSLEAG = isSLEAG && TestHNont((cast(EAG.Nont) F).Sym, EmitErr, SLEAG);
                CheckDefPos((cast(EAG.Nont) F).Actual.Params);
            }
            F = F.Next;
        }
        if (cast(EAG.Rep) Node !is null)
        {
            CheckApplPos(A.Actual.Params);
            if (SLEAG)
                CheckSLEAGCond(A.Actual.Params);
            CheckDefPos(A.Actual.Params);
        }
        CheckApplPos(A.Formal.Params);
        A = A.Next;
    }
    while (A !is null);
    return SLEAG ? isSLEAG : isLEAG;
}

private void Prepare(size_t N) @nogc nothrow
{
    EAG.Rule Node;
    EAG.Alt A;
    EAG.Factor F;
    int P;

    void Traverse(int P)
    {
        void DefPos(int Node)
        {
            if (Node < 0)
            {
                ++VarCnt[-Node];
            }
            else
            {
                for (int n = 1; n <= EAG.MAlt[EAG.NodeBuf[Node]].Arity; ++n)
                    DefPos(EAG.NodeBuf[Node + n]);
            }
        }

        void ApplPos(int Node)
        {
            if (Node < 0)
            {
                ++VarCnt[-Node];
                ++VarAppls[-Node];
            }
            else
            {
                for (int n = 1; n <= EAG.MAlt[EAG.NodeBuf[Node]].Arity; ++n)
                    ApplPos(EAG.NodeBuf[Node + n]);
            }
        }

        while (EAG.ParamBuf[P].Affixform != EAG.nil)
        {
            if (EAG.ParamBuf[P].isDef)
                DefPos(EAG.ParamBuf[P].Affixform);
            else
                ApplPos(EAG.ParamBuf[P].Affixform);
            ++P;
        }
    }

    void InitArray(EAG.ScopeDesc Scope)
    {
        for (int i = Scope.Beg; i < Scope.End; ++i)
        {
            VarCnt[i] = 0;
            VarAppls[i] = 0;
        }
    }

    if (!PreparedHNonts[N])
    {
        Node = EAG.HNont[N].Def;
        if (cast(EAG.Rep) Node !is null)
        {
            InitArray((cast(EAG.Rep) Node).Scope);
            Traverse((cast(EAG.Rep) Node).Formal.Params);
        }
        else if (cast(EAG.Opt) Node !is null)
        {
            InitArray((cast(EAG.Opt) Node).Scope);
            Traverse((cast(EAG.Opt) Node).Formal.Params);
        }
        A = Node.Sub;
        do
        {
            InitArray(A.Scope);
            Traverse(A.Formal.Params);
            F = A.Sub;
            while (F !is null)
            {
                if (cast(EAG.Nont) F !is null)
                    Traverse((cast(EAG.Nont) F).Actual.Params);
                F = F.Next;
            }
            if (cast(EAG.Rep) Node !is null)
            {
                Traverse(A.Actual.Params);
                P = A.Actual.Params;
                while (EAG.ParamBuf[P].Affixform != EAG.nil)
                {
                    if (EAG.ParamBuf[P].isDef && EAG.ParamBuf[P].Affixform < 0)
                        RepVar[-EAG.ParamBuf[P].Affixform] = true;
                    ++P;
                }
            }
            A = A.Next;
        }
        while (A !is null);
        PreparedHNonts[N] = true;
    }
}

public void InitGen(File MOut, int Treatment, Settings settings)
{
    void SetFlags(int Treatment)
    {
        switch (Treatment)
        {
        case parsePass:
            SavePos = true;
            UseConst = false;
            UseRefCnt = false;
            break;
        case onePass:
            break;
        case sSweepPass:
            TraversePass = true;
            break;
        default:
            assert(0);
        }
    }

    if (Generating)
        trace!"resetting SLEAG";
    Mod = MOut;
    SavePos = false;
    TraversePass = false;
    UseConst = !settings.c;
    UseRefCnt = !settings.r;
    SetFlags(Treatment);
    info!"%s %s"(UseRefCnt ? "+rc" : "-rc", UseConst ? "+ct" : "-ct");
    if (!Testing)
        PrepareInit;
    ComputeNodeIdent;
    ComputeConstDat;
    AffixName = new int[EAG.NextParam];
    for (size_t i = EAG.firstParam; i < EAG.NextParam; ++i)
        AffixName[i] = -1;
    NodeName = new int[EAG.NextNode];
    VarName = new int[EAG.NextVar];
    VarDeps = new int[EAG.NextVar];
    VarRefCnt = new int[EAG.NextVar];
    VarDepPos = new int[EAG.NextVar];
    for (size_t i = EAG.firstVar; i < EAG.NextVar; ++i)
    {
        VarRefCnt[i] = 0;
        VarDepPos[i] = -1;
        VarName[i] = -1;
    }
    ActualName = new int[EAG.NextDom];
    FormalName = new int[EAG.NextDom];
    for (size_t i = EAG.firstDom; i < EAG.NextDom; ++i)
    {
        ActualName[i] = -1;
        FormalName[i] = -1;
    }
    HNontVars = new int[EAG.NextHNont];
    HNontFVars = new int[EAG.NextHNont];
    HNontDef = BitArray();
    HNontDef.length = EAG.NextHNont + 1;
    RepAppls = new bool[EAG.NextHNont];
    for (size_t i = EAG.firstHNont; i < EAG.NextHNont; ++i)
        RepAppls[i] = true;
    EmptySet = BitArray();
    EmptySet.length = EAG.NextVar + 1;
    Generating = true;
}

private void PrepareInit() nothrow
{
    VarCnt = new int[EAG.NextVar];
    VarAppls = new int[EAG.NextVar];
    RepVar = BitArray();
    RepVar.length = EAG.NextVar + 1;
    PreparedHNonts = BitArray();
    PreparedHNonts.length = EAG.NextHNont + 1;
}

private void ComputeNodeIdent() nothrow @safe
{
    int N;
    int A;
    int i;
    int temp;

    NodeIdent = new int[EAG.NextMAlt];
    for (A = EAG.firstMAlt; A < EAG.NextMAlt; ++A)
        NodeIdent[A] = -1;
    MaxMAlt = 0;
    for (N = EAG.firstMNont; N < EAG.NextMNont; ++N)
    {
        A = EAG.MNont[N].MRule;
        i = 0;
        while (A != EAG.nil)
        {
            ++i;
            NodeIdent[A] = i;
            A = EAG.MAlt[A].Next;
        }
        if (i > MaxMAlt)
            MaxMAlt = i;
    }
    i = 1;
    while (i <= MaxMAlt)
        i = i * 2;
    MaxMAlt = i;
    RefConst = 0;
    for (A = EAG.firstMAlt; A < EAG.NextMAlt; ++A)
    {
        assert(NodeIdent[A] >= 0);

        temp = NodeIdent[A] + EAG.MAlt[A].Arity * MaxMAlt;
        NodeIdent[A] = temp;
        if (RefConst < NodeIdent[A])
            RefConst = NodeIdent[A];
    }
    i = 1;
    while (i <= RefConst)
        i = i * 2;
    RefConst = i;
}

private void ComputeConstDat() nothrow
{
    int A;
    int ConstPtr;

    void Traverse(size_t N, ref int ConstPtr)
    {
        EAG.Rule Node;
        EAG.Alt A;
        EAG.Factor F;

        void CheckParams(int P, ref int ConstPtr)
        {
            bool isConst;
            int Tree;

            void TraverseTree(int Node, ref int Next)
            {
                if (Node < 0)
                {
                    isConst = false;
                }
                else
                {
                    const Arity = EAG.MAlt[EAG.NodeBuf[Node]].Arity;

                    if (!UseConst || Arity != 0)
                        Next += 1 + Arity;
                    for (int n = 1; n <= Arity; ++n)
                        TraverseTree(EAG.NodeBuf[Node + n], Next);
                }
            }

            while (EAG.ParamBuf[P].Affixform != EAG.nil)
            {
                Tree = EAG.ParamBuf[P].Affixform;
                isConst = true;
                TraverseTree(Tree, AffixSpace[P]);
                if (Tree > 0 && EAG.MAlt[EAG.NodeBuf[Tree]].Arity == 0)
                {
                    if (isConst)
                        AffixPlace[P] = Leaf[EAG.NodeBuf[Tree]];
                }
                else
                {
                    if (isConst)
                    {
                        AffixPlace[P] = ConstPtr;
                        ConstPtr += AffixSpace[P];
                    }
                }
                ++P;
            }
        }

        Node = EAG.HNont[N].Def;
        if (cast(EAG.Rep) Node !is null)
            CheckParams((cast(EAG.Rep) Node).Formal.Params, ConstPtr);
        else if (cast(EAG.Opt) Node !is null)
            CheckParams((cast(EAG.Opt) Node).Formal.Params, ConstPtr);
        A = Node.Sub;
        do
        {
            CheckParams(A.Formal.Params, ConstPtr);
            F = A.Sub;
            while (F !is null)
            {
                if (cast(EAG.Nont) F !is null)
                    CheckParams((cast(EAG.Nont) F).Actual.Params, ConstPtr);
                F = F.Next;
            }
            if (cast(EAG.Rep) Node !is null)
                CheckParams(A.Actual.Params, ConstPtr);
            A = A.Next;
        }
        while (A !is null);
    }

    AffixSpace = new int[EAG.NextParam];
    AffixPlace = new int[EAG.NextParam];
    for (size_t i = EAG.firstParam; i < EAG.NextParam; ++i)
    {
        AffixSpace[i] = 0;
        AffixPlace[i] = -1;
    }
    Leaf = new int[EAG.NextMAlt];
    ConstPtr = EAG.MaxMArity + 1;
    FirstHeap = ConstPtr;
    for (A = EAG.firstMAlt; A < EAG.NextMAlt; ++A)
    {
        if (EAG.MAlt[A].Arity == 0)
        {
            Leaf[A] = ConstPtr;
            ++ConstPtr;
        }
        else
        {
            Leaf[A] = -1;
        }
    }
    foreach (i; EAG.Prod.bitsSet)
        Traverse(i, ConstPtr);
    if (UseConst)
        FirstHeap = ConstPtr;
}

public void FinitGen()
{
    if (!Testing)
        PrepareFinit;
    EmptySet.length = 0;
    NodeIdent = null;
    AffixSpace = null;
    AffixPlace = null;
    Leaf = null;
    AffixName = null;
    NodeName = null;
    VarName = null;
    VarDeps = null;
    VarRefCnt = null;
    VarDepPos = null;
    ActualName = null;
    FormalName = null;
    HNontVars = null;
    HNontFVars = null;
    RepAppls = null;
    Generating = false;
}

private void PrepareFinit() nothrow
{
    VarCnt = null;
    VarAppls = null;
    RepVar.length = 0;
    PreparedHNonts.length = 0;
}

public void GenRepStart(int Sym) @safe
{
    int P;
    int Dom;
    int Next;

    if (!UseRefCnt)
    {
        Next = 0;
        P = (cast(EAG.Rep) EAG.HNont[Sym].Def).Sub.Formal.Params;
        while (EAG.ParamBuf[P].Affixform != EAG.nil)
        {
            if (!EAG.ParamBuf[P].isDef)
                ++Next;
            ++P;
        }
        GenOverflowGuard(Next);
    }
    Dom = EAG.HNont[Sym].Sig;
    P = (cast(EAG.Rep) EAG.HNont[Sym].Def).Sub.Formal.Params;
    while (EAG.DomBuf[Dom] != EAG.nil)
    {
        if (!EAG.ParamBuf[P].isDef)
        {
            if (UseRefCnt)
            {
                Mod.write("GetHeap(0, ");
                GenVar(FormalName[Dom]);
                Mod.write("); ");
            }
            else
            {
                GenVar(FormalName[Dom]);
                Mod.write(" = NextHeap; ++NextHeap; ");
            }
            GenVar(AffixName[P]);
            Mod.write(" = ");
            GenVar(FormalName[Dom]);
            Mod.write(";\n");
        }
        ++P;
        ++Dom;
    }
}

public void GenDeclarations(Settings settings)
{
    Input Fix;
    string name;
    long TabTimeStamp;

    void InclFix(char Term)
    {
        import std.conv : to;
        import std.exception : enforce;

        char c = Fix.front.to!char;

        while (c != Term)
        {
            enforce(c != 0,
                    "error: unexpected end of eSLEAGGen.fix.d");

            Mod.write(c);
            Fix.popFront;
            c = Fix.front.to!char;
        }
        Fix.popFront;
    }

    void SkipFix(char Term)
    {
        import std.conv : to;
        import std.exception : enforce;

        char c = Fix.front.to!char;

        while (c != Term)
        {
            enforce(c != 0,
                    "error: unexpected end of eSLEAGGen.fix.d");

            Fix.popFront;
            c = Fix.front.to!char;
        }
        Fix.popFront;
    }

    void GenTabFile(long TabTimeStamp)
    {
        const errVal = 0;
        const magic = 1_818_326_597;
        int i;
        int P;
        int Next;
        int[] Heap;

        void SynTree(int Node, ref int Next)
        {
            int n;
            int Node1;
            int Next1;

            Heap[Next] = NodeIdent[EAG.NodeBuf[Node]];
            Next1 = Next;
            Next += 1 + EAG.MAlt[EAG.NodeBuf[Node]].Arity;
            for (n = 1; n <= EAG.MAlt[EAG.NodeBuf[Node]].Arity; ++n)
            {
                Node1 = EAG.NodeBuf[Node + n];
                if (EAG.MAlt[EAG.NodeBuf[Node1]].Arity == 0)
                {
                    Heap[Next1 + n] = Leaf[EAG.NodeBuf[Node1]];
                }
                else
                {
                    Heap[Next1 + n] = Next;
                    SynTree(Node1, Next);
                }
            }
        }

        File Tab = File(settings.path(name), "w");

        Tab.writefln!"long %s"(magic);
        Tab.writefln!"long %s"(TabTimeStamp);
        Tab.writefln!"long %s"(FirstHeap - 1);
        Heap = new int[FirstHeap];
        Heap[errVal] = 0;
        for (i = 1; i <= EAG.MaxMArity; ++i)
            Heap[i] = errVal;
        if (UseConst)
        {
            for (i = EAG.firstMAlt; i < EAG.NextMAlt; ++i)
            {
                if (Leaf[i] >= errVal)
                    Heap[Leaf[i]] = NodeIdent[i];
            }
            for (P = EAG.firstParam; P < EAG.NextParam; ++P)
            {
                if (EAG.ParamBuf[P].Affixform != EAG.nil && AffixPlace[P] >= 0)
                {
                    Next = AffixPlace[P];
                    SynTree(EAG.ParamBuf[P].Affixform, Next);
                }
            }
        }
        for (i = 0; i < FirstHeap; ++i)
            Tab.writefln!"long %s"(Heap[i]);
        Tab.writefln!"long %s"(TabTimeStamp);
    }

    if (TraversePass)
        name = EAG.BaseName ~ "Eval.EvalTab";
    else
        name = EAG.BaseName ~ ".EvalTab";
    TabTimeStamp = MonoTime.currTime.ticks;
    Fix = read("fix/epsilon/sleaggen.fix.d");
    InclFix('$');
    Mod.write(FirstHeap - 1);
    InclFix('$');
    Mod.write(MaxMAlt);
    InclFix('$');
    if (SavePos)
        Mod.write("Eval.TreeType");
    else
        Mod.write("long");
    InclFix('$');
    if (SavePos)
        Mod.write("Eval.TreeType[]");
    else
        Mod.write("HeapType[]");
    InclFix('$');
    if (SavePos)
        InclFix('$');
    else
        SkipFix('$');
    InclFix('$');
    Mod.write(EAG.MaxMArity + 1);
    InclFix('$');
    Mod.write(RefConst);
    InclFix('$');
    if (SavePos)
    {
        SkipFix('$');
        InclFix('$');
    }
    else
    {
        InclFix('$');
        SkipFix('$');
    }
    if (UseRefCnt)
    {
        InclFix('$');
        SkipFix('$');
    }
    else
    {
        SkipFix('$');
        InclFix('$');
    }
    InclFix('$');
    if (!TraversePass)
        Mod.write("S.");
    InclFix('$');
    if (UseRefCnt)
        InclFix('$');
    else
        SkipFix('$');
    InclFix('$');
    Mod.write(name);
    InclFix('$');
    Mod.write(TabTimeStamp);
    InclFix('$');
    if (SavePos)
        InclFix('$');
    else
        SkipFix('$');
    InclFix('$');
    GenTabFile(TabTimeStamp);
}

public bool PosNeeded(int P) @nogc nothrow @safe
{
    while (EAG.ParamBuf[P].Affixform != EAG.nil)
    {
        if (EAG.ParamBuf[P].isDef)
        {
            const V = -EAG.ParamBuf[P].Affixform;

            if (V < 0)
                return true;
            else if (EAG.Var[V].Def)
                return true;
            else if (EAG.Var[EAG.Var[V].Neg].Def)
                return true;
        }
        ++P;
    }
    return false;
}

public void GenRepAlt(int Sym, EAG.Alt A)
{
    int P;
    int P1;
    int Dom;
    int Tree;
    int Next;
    const Guard = !RepAppls[Sym];

    GenSynPred(Sym, A.Actual.Params);
    if (SavePos)
        Mod.write("PushPos;\n");
    P = A.Actual.Params;
    Dom = EAG.HNont[Sym].Sig;
    while (EAG.ParamBuf[P].Affixform != EAG.nil)
    {
        if (!EAG.ParamBuf[P].isDef && AffixName[P] != FormalName[Dom])
        {
            GenVar(FormalName[Dom]);
            Mod.write(" = ");
            GenVar(AffixName[P]);
            Mod.write(";\n");
        }
        ++P;
        ++Dom;
    }
    P1 = A.Actual.Params;
    Dom = EAG.HNont[Sym].Sig;
    P = A.Formal.Params;
    if (!UseRefCnt)
        GetAffixSpace(P);
    GenHangIn(P, Guard);
    Next = 0;
    while (EAG.ParamBuf[P].Affixform != EAG.nil)
    {
        if (!EAG.ParamBuf[P].isDef)
        {
            Tree = EAG.ParamBuf[P].Affixform;
            if (SavePos)
            {
                Mod.write("PopPos(");
                Mod.write(EAG.MAlt[EAG.NodeBuf[Tree]].Arity);
                Mod.write(");\n");
            }
            if (Tree > 0 && !(UseConst && AffixPlace[P] >= 0))
            {
                if (Guard)
                {
                    Mod.write("if (");
                    GenVar(NodeName[Tree]);
                    Mod.write(" != undef)\n");
                    Mod.write("{\n");
                }
                if (UseRefCnt)
                    Gen1SynTree(Tree, RepVar, EAG.Pred[Sym]);
                else
                    GenSynTree(Tree, RepVar, Next);
                Mod.write("\n");
                if (Guard)
                    Mod.write("}\n");
            }
            if (Guard && VarAppls[-EAG.ParamBuf[P1].Affixform] == 0)
            {
                GenVar(AffixName[P1]);
                Mod.write(" = undef;\n");
            }
        }
        ++P;
        ++P1;
        ++Dom;
    }
    if (!UseRefCnt)
        GenHeapInc(Next);
}

public void GenRepEnd(int Sym)
{
    int P;
    int P1;
    int Dom;
    int Tree;
    int Next;
    const Guard = false; // TODO: eliminate dead code?

    InitScope((cast(EAG.Rep) EAG.HNont[Sym].Def).Scope);
    P = (cast(EAG.Rep) EAG.HNont[Sym].Def).Formal.Params;
    P1 = EAG.HNont[Sym].Def.Sub.Actual.Params;
    Dom = EAG.HNont[Sym].Sig;
    GenAnalPred(Sym, P);
    if (!UseRefCnt)
        GetAffixSpace(P);
    GenHangIn(P, Guard);
    Next = 0;
    while (EAG.ParamBuf[P].Affixform != EAG.nil)
    {
        if (!EAG.ParamBuf[P].isDef)
        {
            Tree = EAG.ParamBuf[P].Affixform;
            if (SavePos)
            {
                Mod.write("PopPos(");
                Mod.write(EAG.MAlt[EAG.NodeBuf[Tree]].Arity);
                Mod.write(");\n");
            }
            if (Tree > 0 && !(UseConst && AffixPlace[P] >= 0))
            {
                if (Guard)
                {
                    Mod.write("if (");
                    GenVar(NodeName[Tree]);
                    Mod.write(" != undef)\n");
                    Mod.write("{\n");
                }
                if (UseRefCnt)
                    Gen1SynTree(Tree, EmptySet, EAG.Pred[Sym]);
                else
                    GenSynTree(Tree, EmptySet, Next);
                Mod.write("\n");
                if (Guard)
                    Mod.write("}\n");
            }
            if (UseRefCnt)
            {
                GenVar(AffixName[P]);
                Mod.write(" = ");
                GenVar(FormalName[Dom]);
                Mod.write("; ");
            }
            GenVar(FormalName[Dom]);
            Mod.write(" = ");
            GenHeap(FormalName[Dom], 0);
            Mod.write(";\n");
            if (UseRefCnt)
            {
                GenHeap(AffixName[P], 0);
                Mod.write(" = 0; FreeHeap(");
                GenVar(AffixName[P]);
                Mod.write(");\n");
            }
        }
        ++P;
        ++P1;
        ++Dom;
    }
    if (!UseRefCnt)
        GenHeapInc(Next);
}

private void GenHangIn(int P, bool Guard)
{
    int Tree;
    int Next;

    void FreeVariables(int Node)
    {
        if (Node < 0)
        {
            if (!RepVar[-Node])
            {
                Mod.write("FreeHeap(");
                GenVar(VarName[-Node]);
                Mod.write("); ");
            }
        }
        else
        {
            for (int n = 1; n <= EAG.MAlt[EAG.NodeBuf[Node]].Arity; ++n)
                FreeVariables(EAG.NodeBuf[Node + n]);
        }
    }

    Next = 0;
    while (EAG.ParamBuf[P].Affixform != EAG.nil)
    {
        if (!EAG.ParamBuf[P].isDef)
        {
            Tree = EAG.ParamBuf[P].Affixform;
            if (Guard)
            {
                Mod.write("if (");
                GenVar(AffixName[P]);
                Mod.write(" != undef)\n");
                Mod.write("{\n");
            }
            if (UseConst && AffixPlace[P] >= 0)
            {
                GenHeap(AffixName[P], 0);
                Mod.write(" = ");
                Mod.write(AffixPlace[P]);
                Mod.write(";\n");
                if (UseRefCnt)
                    GenIncRefCnt(-AffixPlace[P], 1);
            }
            else if (Tree < 0)
            {
                if (AffixName[P] != VarName[-Tree])
                {
                    GenHeap(AffixName[P], 0);
                    Mod.write(" = ");
                    GenVar(VarName[-Tree]);
                    Mod.write(";\n");
                    if (Guard)
                    {
                        Mod.write("}\n");
                        Mod.write("else\n");
                        Mod.write("{\n");
                        Mod.write("FreeHeap(");
                        GenVar(VarName[-Tree]);
                        Mod.write(");\n");
                    }
                }
            }
            else
            {
                if (UseRefCnt)
                {
                    Mod.write("GetHeap(");
                    Mod.write(EAG.MAlt[EAG.NodeBuf[Tree]].Arity);
                    Mod.write(", ");
                    GenVar(NodeName[Tree]);
                    Mod.write("); ");
                    GenHeap(AffixName[P], 0);
                    Mod.write(" = ");
                    GenVar(NodeName[Tree]);
                    Mod.write(";\n");
                    if (Guard)
                    {
                        Mod.write("}\n");
                        Mod.write("else\n");
                        Mod.write("{\n");
                        FreeVariables(Tree);
                    }
                }
                else
                {
                    GenHeap(AffixName[P], 0);
                    Mod.write(" = NextHeap");
                    if (Next != 0)
                    {
                        Mod.write(" + ");
                        Mod.write(Next);
                    }
                    Mod.write(";\n");
                    Next += AffixSpace[P];
                    if (Guard)
                    {
                        Mod.write("}\n");
                        Mod.write("else\n");
                        Mod.write("{\n");
                    }
                }
                if (Guard)
                {
                    GenVar(NodeName[Tree]);
                    Mod.write(" = undef;\n");
                }
            }
            if (Guard)
                Mod.write("}\n");
        }
        ++P;
    }
}

public void GenPredProcs()
{
    void GenPredCover(size_t N)
    in (EAG.Pred[N])
    {
        int Dom;
        int i;

        Mod.write("void Check");
        Mod.write(N);
        Mod.write("(string ErrMsg");
        GenFormalParams(N, No.parNeeded);
        Mod.write(")\n");
        Mod.write("{\n");
        Mod.write("if (!Pred");
        Mod.write(N);
        Mod.write("(");
        Dom = EAG.HNont[N].Sig;
        i = 1;
        if (EAG.DomBuf[Dom] != EAG.nil)
        {
            while (true)
            {
                GenVar(i);
                ++Dom;
                ++i;
                if (EAG.DomBuf[Dom] == EAG.nil)
                    break;
                Mod.write(", ");
            }
        }
        Mod.write("))\n");
        Mod.write("{\n");
        Dom = EAG.HNont[N].Sig;
        i = 1;
        while (EAG.DomBuf[Dom] > 0)
            ++Dom;
        if (EAG.DomBuf[Dom] != EAG.nil)
        {
            Mod.write("if (");
            while (true)
            {
                GenVar(i);
                Mod.write(" != errVal ");
                do
                {
                    ++Dom;
                    ++i;
                }
                while (!(EAG.DomBuf[Dom] <= 0));
                if (EAG.DomBuf[Dom] == EAG.nil)
                    break;
                Mod.write(" && ");
            }
            Mod.write(") PredError(ErrMsg);\n");
        }
        else
        {
            Mod.write("Error(ErrMsg);\n");
        }
        Mod.write("}\n");
        Mod.write("}\n\n");
    }

    void GenPredicateCode(size_t N)
    {
        EAG.Rule Node;
        EAG.Alt A;
        EAG.ScopeDesc Scope;
        int P;
        int Level;
        int AltLevel;
        int i;

        void CleanLevel(int Level)
        {
            if (Level >= 1)
            {
                for (int i = 0; i < Level; ++i)
                    Mod.write("} ");
                Mod.write("\n");
            }
        }

        void FreeParamTrees(int P)
        {
            while (EAG.ParamBuf[P].Affixform != EAG.nil)
            {
                if (EAG.ParamBuf[P].isDef)
                    GenFreeHeap(AffixName[P]);
                ++P;
            }
        }

        void TraverseFactor(EAG.Factor F, int FormalParams)
        {
            int Level;

            if (F !is null)
            {
                assert(cast(EAG.Nont) F !is null);
                assert(EAG.Pred[(cast(EAG.Nont) F).Sym]);

                GenSynPred(N, (cast(EAG.Nont) F).Actual.Params);
                Mod.write("if (Pred");
                Mod.write((cast(EAG.Nont) F).Sym);
                GenActualParams((cast(EAG.Nont) F).Actual.Params, true);
                Mod.write(") //");
                Mod.write(EAG.HNontRepr((cast(EAG.Nont) F).Sym));
                Mod.write("\n");
                Mod.write("{\n");
                GenAnalPred(N, (cast(EAG.Nont) F).Actual.Params);
                Level = IfLevel;
                TraverseFactor(F.Next, FormalParams);
                CleanLevel(Level);
                Mod.write("}\n");
                if (UseRefCnt)
                    FreeParamTrees((cast(EAG.Nont) F).Actual.Params);
            }
            else
            {
                if (cast(EAG.Rep) Node !is null)
                {
                    GenSynPred(N, A.Actual.Params);
                    Mod.write("if (Pred");
                    Mod.write(N);
                    GenActualParams(A.Actual.Params, true);
                    Mod.write(") //");
                    Mod.write(EAG.HNontRepr(N));
                    Mod.write("\n");
                    Mod.write("{\n");
                    GenAnalPred(N, A.Actual.Params);
                    Level = IfLevel;
                    GenSynPred(N, FormalParams);
                    Mod.write("Failed = false;\n");
                    CleanLevel(Level);
                    Mod.write("}\n");
                    if (UseRefCnt)
                        FreeParamTrees(A.Actual.Params);
                }
                else
                {
                    GenSynPred(N, FormalParams);
                    Mod.write("Failed = false;\n");
                }
            }
        }

        Node = EAG.HNont[N].Def;
        AltLevel = 0;
        Mod.write("Failed = true;\n");
        if (cast(EAG.Rep) Node !is null || cast(EAG.Opt) Node !is null)
        {
            if (cast(EAG.Opt) Node !is null)
            {
                P = (cast(EAG.Opt) Node).Formal.Params;
                Scope = (cast(EAG.Opt) Node).Scope;
            }
            else
            {
                P = (cast(EAG.Rep) Node).Formal.Params;
                Scope = (cast(EAG.Rep) Node).Scope;
            }
            InitScope(Scope);
            GenAnalPred(N, P);
            Level = IfLevel;
            GenSynPred(N, P);
            Mod.write("Failed = false;\n");
            CleanLevel(Level);
            ++AltLevel;
        }
        A = Node.Sub;
        while (true)
        {
            if (AltLevel > 0)
            {
                Mod.write("if (Failed) // ");
                Mod.write(AltLevel + 1);
                Mod.write(". Alternative\n");
                Mod.write("{\n");
            }
            InitScope(A.Scope);
            GenAnalPred(N, A.Formal.Params);
            Level = IfLevel;
            TraverseFactor(A.Sub, A.Formal.Params);
            CleanLevel(Level);
            ++AltLevel;
            A = A.Next;
            if (A is null)
            {
                break;
            }
        }
        for (i = 1; i < AltLevel; ++i)
            Mod.write("} ");
        Mod.write("\n");
        P = Node.Sub.Formal.Params;
        if (UseRefCnt)
            FreeParamTrees(P);
        Mod.write("if (Failed)\n");
        Mod.write("{\n");
        while (EAG.ParamBuf[P].Affixform != EAG.nil)
        {
            if (!EAG.ParamBuf[P].isDef)
            {
                GenVar(AffixName[P]);
                Mod.write(" = errVal;\n");
                if (UseRefCnt)
                    Mod.write("Heap[errVal] += refConst;\n");
            }
            ++P;
        }
        Mod.write("}\n");
    }

    foreach (N; EAG.Pred.bitsSet)
        GenPredCover(N);
    foreach (N; EAG.Pred.bitsSet)
    {
        ComputeVarNames(N, No.embed);
        Mod.write("bool Pred");
        Mod.write(N);
        GenFormalParams(N, Yes.parNeeded);
        Mod.write(" // ");
        Mod.write(EAG.HNontRepr(N));
        Mod.write("\n");
        Mod.write("{\n");
        GenVarDecl(N);
        GenPredicateCode(N);
        Mod.write("return !Failed;\n");
        Mod.write("}\n\n");
    }
}

public void ComputeVarNames(size_t N, Flag!"embed" embed)
{
    int[] FreeVar;
    int[] RefCnt;
    int Top;
    int NextFreeVar;

    void VarExpand()
    {
        if (NextFreeVar >= RefCnt.length)
        {
            auto Int = new int[2 * RefCnt.length];

            for (int i = 0; i < NextFreeVar; ++i)
                Int[i] = RefCnt[i];
            for (size_t i = NextFreeVar; i < Int.length; ++i)
                Int[i] = 0;
            RefCnt = Int;
        }
        if (Top >= FreeVar.length)
        {
            auto Int = new int[2 * FreeVar.length];

            for (int i = 0; i < Top; ++i)
                Int[i] = FreeVar[i];
            FreeVar = Int;
        }
    }

    int GetFreeVar()
    {
        int Var;

        if (Top > 0)
        {
            --Top;
            Var = FreeVar[Top];
        }
        else
        {
            ++NextFreeVar;
            if (NextFreeVar >= RefCnt.length)
                VarExpand;
            RefCnt[NextFreeVar] = 0;
            Var = NextFreeVar;
        }
        trace!"RC: -%s"(Var);
        return Var;
    }

    void Dispose(int Var)
    {
        --RefCnt[Var];
        if (RefCnt[Var] == 0)
        {
            trace!"RC: +%s"(Var);
            FreeVar[Top] = Var;
            ++Top;
            if (Top >= FreeVar.length)
                VarExpand;
        }
    }

    void Traverse(size_t N)
    {
        EAG.Rule Node;
        EAG.Alt A;
        EAG.Factor F;
        int Dom;
        int P;
        int Tree;
        bool Repetition;
        bool isPred;

        void CheckDefPos(int P)
        {
            int Tree;
            int V;

            void DefPos(int Node, int Var)
            {
                int n;
                int Arity;
                int Node1;
                int Var1;
                int V;
                int Vn;
                bool NeedVar;

                if (Node < 0)
                {
                    V = -Node;
                    if (!EAG.Var[V].Def)
                    {
                        EAG.Var[V].Def = true;
                        if (VarName[V] < 0)
                        {
                            VarName[V] = GetFreeVar;
                            ++RefCnt[VarName[V]];
                        }
                        if (EAG.Var[EAG.Var[V].Neg].Def)
                        {
                            Vn = EAG.Var[V].Neg;
                            --VarDeps[V];
                            --VarDeps[Vn];
                            if (VarDeps[Vn] == 0)
                            {
                                VarDepPos[Vn] = P;
                                Dispose(VarName[Vn]);
                            }
                        }
                    }
                    else
                    {
                        if (VarDeps[V] == 1)
                            VarDepPos[V] = P;
                    }
                    --VarDeps[V];
                    if (VarDeps[V] == 0)
                        Dispose(VarName[V]);
                }
                else
                {
                    Arity = EAG.MAlt[EAG.NodeBuf[Node]].Arity;
                    if (Arity != 0)
                        NodeName[Node] = Var;
                    for (n = 1; n <= Arity; ++n)
                    {
                        Node1 = EAG.NodeBuf[Node + n];
                        NeedVar = ((isPred || UseRefCnt) && Var == AffixName[P] || n != Arity)
                            && Node1 >= 0
                            && EAG.MAlt[EAG.NodeBuf[Node1]].Arity > 0;
                        if (NeedVar)
                        {
                            Var1 = GetFreeVar;
                            ++RefCnt[Var1];
                        }
                        else
                        {
                            Var1 = Var;
                        }
                        DefPos(Node1, Var1);
                        if (NeedVar)
                            Dispose(Var1);
                    }
                }
            }

            while (EAG.ParamBuf[P].Affixform != EAG.nil)
            {
                Tree = EAG.ParamBuf[P].Affixform;
                if (EAG.ParamBuf[P].isDef)
                {
                    if (Tree < 0 && VarName[-Tree] < 0)
                    {
                        V = -Tree;
                        VarName[V] = AffixName[P];
                        ++RefCnt[VarName[V]];
                    }
                    DefPos(Tree, AffixName[P]);
                }
                ++P;
            }
        }

        void CheckApplPos(int P, bool Repetition)
        {
            int Tree;
            int V;
            int P1;

            void ApplPos(int Node, int Var)
            {
                int n;
                int Arity;
                int Node1;
                int Var1;
                int V;
                bool NeedVar;

                if (Node < 0)
                {
                    V = -Node;
                    --VarDeps[V];
                    if (VarDeps[V] == 0)
                        Dispose(VarName[V]);
                    if (VarDepPos[V] >= 0)
                        VarDepPos[V] = -1;
                }
                else
                {
                    Arity = EAG.MAlt[EAG.NodeBuf[Node]].Arity;
                    NodeName[Node] = Var;
                    for (n = 1; n <= Arity; ++n)
                    {
                        Node1 = EAG.NodeBuf[Node + n];
                        NeedVar = !(UseConst && AffixPlace[P] > 0)
                            && UseRefCnt
                            && (Var == AffixName[P] || n != Arity)
                            && Node1 >= 0
                            && EAG.MAlt[EAG.NodeBuf[Node1]].Arity > 0;
                        if (NeedVar)
                        {
                            Var1 = GetFreeVar;
                            ++RefCnt[Var1];
                        }
                        else
                        {
                            Var1 = Var;
                        }
                        ApplPos(Node1, Var1);
                        if (NeedVar)
                            Dispose(Var1);
                    }
                }
            }

            P1 = P;
            while (EAG.ParamBuf[P].Affixform != EAG.nil)
            {
                if (!EAG.ParamBuf[P].isDef)
                {
                    Tree = EAG.ParamBuf[P].Affixform;
                    if (Tree < 0 && VarName[-Tree] < 0)
                    {
                        V = -Tree;
                        VarName[V] = AffixName[P];
                        ++RefCnt[VarName[V]];
                    }
                    if (!(UseConst && AffixPlace[P] > 0) && Repetition && Tree >= 0)
                    {
                        NodeName[Tree] = GetFreeVar;
                        ++RefCnt[NodeName[Tree]];
                        ApplPos(Tree, NodeName[Tree]);
                    }
                    else
                    {
                        ApplPos(Tree, AffixName[P]);
                    }
                }
                ++P;
            }
            if (Repetition)
            {
                while (EAG.ParamBuf[P1].Affixform != EAG.nil)
                {
                    if (!EAG.ParamBuf[P1].isDef && !(UseConst && AffixPlace[P1] > 0))
                    {
                        Tree = EAG.ParamBuf[P1].Affixform;
                        if (Tree >= 0)
                            Dispose(NodeName[Tree]);
                    }
                    ++P1;
                }
            }
        }

        void GetFormalParamNames(size_t N, int P)
        {
            bool Repetition = !EAG.Pred[N] && cast(EAG.Rep) EAG.HNont[N].Def !is null;
            int Dom = EAG.HNont[N].Sig;
            int Tree;
            int V;

            while (EAG.ParamBuf[P].Affixform != EAG.nil)
            {
                if (Repetition)
                {
                    AffixName[P] = ActualName[Dom];
                }
                else
                {
                    AffixName[P] = FormalName[Dom];
                    Tree = EAG.ParamBuf[P].Affixform;
                    if (!EAG.ParamBuf[P].isDef && Tree < 0)
                    {
                        V = -Tree;
                        VarName[V] = AffixName[P];
                        ++RefCnt[VarName[V]];
                    }
                }
                ++P;
                ++Dom;
            }
        }

        void GetActualParamNames(size_t N, int P)
        {
            int FindVarName(int P, int VarName)
            {
                while (AffixName[P] != VarName)
                    ++P;
                return P;
            }

            bool Repetition = !EAG.Pred[N] && cast(EAG.Rep) EAG.HNont[N].Def !is null;
            int P1 = P;
            int Tree;
            int V;

            while (EAG.ParamBuf[P].Affixform != EAG.nil)
            {
                Tree = EAG.ParamBuf[P].Affixform;
                if (AffixName[P] < 0)
                {
                    if (Tree < 0 && VarName[-Tree] >= 0)
                    {
                        V = -Tree;
                        if (!EAG.ParamBuf[P].isDef)
                        {
                            if (Repetition && VarDeps[V] > 1)
                            {
                                AffixName[P] = GetFreeVar;
                            }
                            else if (!EAG.Pred[N] && EAG.HNont[N].anonymous)
                            {
                                AffixName[P] = VarName[V];
                                if (FindVarName(P1, VarName[V]) != P)
                                    AffixName[P] = GetFreeVar;
                            }
                            else
                            {
                                AffixName[P] = VarName[V];
                            }
                        }
                        else
                        {
                            AffixName[P] = VarName[V];
                            if (EAG.Var[V].Def || FindVarName(P1, VarName[V]) != P)
                                AffixName[P] = GetFreeVar;
                        }
                    }
                    else
                    {
                        AffixName[P] = GetFreeVar;
                    }
                }
                ++RefCnt[AffixName[P]];
                if (isPred && EAG.ParamBuf[P].isDef)
                    ++RefCnt[AffixName[P]];
                ++P;
            }
        }

        void FreeActualParamNames(int P)
        {
            while (EAG.ParamBuf[P].Affixform != EAG.nil)
            {
                Dispose(AffixName[P]);
                ++P;
            }
        }

        void FreeAllDefPosVarNames(EAG.Alt A)
        {
            EAG.Factor F;

            void FreeVarNames(int P)
            {
                while (EAG.ParamBuf[P].Affixform != EAG.nil)
                {
                    if (EAG.ParamBuf[P].isDef)
                        Dispose(AffixName[P]);
                    ++P;
                }
            }

            F = A.Sub;
            while (F !is null)
            {
                if (cast(EAG.Nont) F !is null)
                    FreeVarNames((cast(EAG.Nont) F).Actual.Params);
                F = F.Next;
            }
            if (cast(EAG.Rep) Node !is null)
                FreeVarNames(A.Actual.Params);
        }

        void InitComputation(EAG.ScopeDesc Scope)
        {
            trace!"RC: enter";
            InitScope(Scope);
            for (int i = Scope.Beg; i < Scope.End; ++i)
            {
                VarDeps[i] = VarCnt[i];
                if (EAG.Var[i].Neg != EAG.nil)
                    ++VarDeps[i];
            }
        }

        void FinitComputation(EAG.ScopeDesc Scope)
        {
            trace!"RC: exit";
            for (int i = Scope.Beg; i < Scope.End; ++i)
            {
                VarRefCnt[i] = VarAppls[i];
                if (VarDepPos[i] >= 0)
                    ++VarRefCnt[i];
                trace!`RC: "%s" %s V%s (%s)`(EAG.VarRepr(i), VarDeps[i], VarName[i], RefCnt[VarName[i]]);
            }
        }

        Prepare(N);
        trace!`RC: begin "%s": RefCnt=%s`(EAG.HNontRepr(N), RefCnt[0 .. NextFreeVar + 1]);
        scope (exit)
            trace!`RC: end "%s": RefCnt=%s`(EAG.HNontRepr(N), RefCnt[0 .. NextFreeVar + 1]);
        Node = EAG.HNont[N].Def;
        isPred = EAG.Pred[N];
        Repetition = !isPred && cast(EAG.Rep) Node !is null;
        Dom = EAG.HNont[N].Sig;
        while (EAG.DomBuf[Dom] != EAG.nil)
        {
            if (FormalName[Dom] < 0)
                FormalName[Dom] = GetFreeVar;
            ++RefCnt[FormalName[Dom]];
            ++Dom;
        }
        if (Repetition)
        {
            Dom = EAG.HNont[N].Sig;
            P = (cast(EAG.Rep) Node).Formal.Params;
            while (EAG.DomBuf[Dom] != EAG.nil)
            {
                ActualName[Dom] = FormalName[Dom];
                if (!EAG.ParamBuf[P].isDef)
                {
                    ActualName[Dom] = GetFreeVar;
                    ++RefCnt[ActualName[Dom]];
                }
                ++Dom;
                ++P;
            }
        }
        A = Node.Sub;
        do
        {
            InitComputation(A.Scope);
            trace!"RC: RefCnt=%s"(RefCnt[0 .. NextFreeVar + 1]);
            GetFormalParamNames(N, A.Formal.Params);
            if (Repetition)
            {
                Dom = EAG.HNont[N].Sig;
                P = A.Actual.Params;
                while (EAG.ParamBuf[P].Affixform != EAG.nil)
                {
                    if (EAG.ParamBuf[P].isDef)
                    {
                        AffixName[P] = ActualName[Dom];
                        if (EAG.ParamBuf[P].Affixform < 0)
                        {
                            VarName[-EAG.ParamBuf[P].Affixform] = AffixName[P];
                            ++RefCnt[AffixName[P]];
                        }
                    }
                    ++P;
                    ++Dom;
                }
            }
            CheckDefPos(A.Formal.Params);
            F = A.Sub;
            while (F !is null)
            {
                if (cast(EAG.Nont) F !is null)
                {
                    GetActualParamNames((cast(EAG.Nont) F).Sym, (cast(EAG.Nont) F).Actual.Params);
                    CheckApplPos((cast(EAG.Nont) F).Actual.Params, false);
                    if (embed
                            && EAG.Prod[(cast(EAG.Nont) F).Sym]
                            && !EAG.Pred[(cast(EAG.Nont) F).Sym]
                            && EAG.HNont[(cast(EAG.Nont) F).Sym].anonymous)
                    {
                        Dom = EAG.HNont[(cast(EAG.Nont) F).Sym].Sig;
                        P = (cast(EAG.Nont) F).Actual.Params;
                        while (EAG.DomBuf[Dom] != EAG.nil)
                        {
                            FormalName[Dom] = AffixName[P];
                            ++Dom;
                            ++P;
                        }
                        Traverse((cast(EAG.Nont) F).Sym);
                    }
                    CheckDefPos((cast(EAG.Nont) F).Actual.Params);
                    FreeActualParamNames((cast(EAG.Nont) F).Actual.Params);
                }
                F = F.Next;
            }
            if (cast(EAG.Rep) Node !is null)
            {
                GetActualParamNames(N, A.Actual.Params);
                CheckApplPos(A.Actual.Params, false);
                CheckDefPos(A.Actual.Params);
                FreeActualParamNames(A.Actual.Params);
            }
            CheckApplPos(A.Formal.Params, Repetition);
            if (isPred)
                FreeAllDefPosVarNames(A);
            FinitComputation(A.Scope);
            trace!"RC: RefCnt=%s"(RefCnt[0 .. NextFreeVar + 1]);
            A = A.Next;
        }
        while (A !is null);
        if (cast(EAG.Rep) Node !is null)
        {
            InitComputation((cast(EAG.Rep) Node).Scope);
            GetFormalParamNames(N, (cast(EAG.Rep) Node).Formal.Params);
            CheckDefPos((cast(EAG.Rep) Node).Formal.Params);
            CheckApplPos((cast(EAG.Rep) Node).Formal.Params, true);
            FinitComputation((cast(EAG.Rep) Node).Scope);
        }
        else if (cast(EAG.Opt) Node !is null)
        {
            InitComputation((cast(EAG.Opt) Node).Scope);
            GetFormalParamNames(N, (cast(EAG.Opt) Node).Formal.Params);
            CheckDefPos((cast(EAG.Opt) Node).Formal.Params);
            CheckApplPos((cast(EAG.Opt) Node).Formal.Params, false);
            FinitComputation((cast(EAG.Opt) Node).Scope);
        }
        if (Repetition)
        {
            P = (cast(EAG.Rep) Node).Formal.Params;
            while (EAG.ParamBuf[P].Affixform != EAG.nil)
            {
                if (!EAG.ParamBuf[P].isDef)
                    Dispose(AffixName[P]);
                ++P;
            }
        }
        Dom = EAG.HNont[N].Sig;
        while (EAG.DomBuf[Dom] != EAG.nil)
        {
            Dispose(FormalName[Dom]);
            ++Dom;
        }
    }

    void Bla(size_t N) // TODO: fix name
    {
        if (cast(EAG.Rep) EAG.HNont[N].Def !is null)
        {
            EAG.Alt A = EAG.HNont[N].Def.Sub;

            do
            {
                int P = A.Actual.Params;
                while (EAG.ParamBuf[P].Affixform != EAG.nil)
                {
                    if (EAG.ParamBuf[P].isDef)
                        RepAppls[N] = RepAppls[N] && VarAppls[-EAG.ParamBuf[P].Affixform] == 1;
                    ++P;
                }
                A = A.Next;
            }
            while (A !is null);
        }
    }

    assert(EAG.Prod[N]);
    assert(!HNontDef[N]);

    FreeVar = new int[63];
    RefCnt = new int[63];
    Bla(N);
    NextFreeVar = 0;
    Top = 0;
    Traverse(N);
    HNontVars[N] = NextFreeVar;
    HNontDef[N] = true;
}

public void GenFormalParams(size_t N, Flag!"parNeeded" parNeeded)
{
    int Dom = EAG.HNont[N].Sig;
    int i = 1;

    if (parNeeded)
        Mod.write("(");
    if (EAG.DomBuf[Dom] != EAG.nil)
    {
        if (!parNeeded)
            Mod.write(", ");
        while (true)
        {
            if (EAG.DomBuf[Dom] > 0)
                Mod.write("ref ");
            Mod.write("HeapType ");
            GenVar(i);
            ++i;
            ++Dom;
            if (EAG.DomBuf[Dom] == EAG.nil)
                break;
            Mod.write(", ");
        }
    }
    if (parNeeded)
    {
        Mod.write(")");
        if (EAG.Pred[N])
        {
            // Mod.write(": BOOLEAN");
        }
    }
    HNontFVars[N] = i;
}

public void GenVarDecl(size_t N)
{
    if (HNontVars[N] - HNontFVars[N] >= 0)
    {
        for (int i = HNontFVars[N]; i <= HNontVars[N]; ++i)
        {
            Mod.write("HeapType ");
            GenVar(i);
            Mod.write(";\n");
        }
    }
    if (EAG.Pred[N])
        Mod.write("bool Failed;\n");
}

public void InitScope(EAG.ScopeDesc Scope) @nogc nothrow @safe
{
    for (int i = Scope.Beg; i < Scope.End; ++i)
        EAG.Var[i].Def = false;
}

public void GenPredCall(int N, int ActualParams)
in (EAG.Pred[N])
{
    Mod.write("Check");
    Mod.write(N);
    Mod.write(`("`);
    if (EAG.HNont[N].anonymous)
        Mod.write("in ");
    Mod.write("'");
    Mod.write(EAG.NamedHNontRepr(N));
    Mod.write(`'"`);
    GenActualParams(ActualParams, false);
    Mod.write(");\n");
}

public void GenActualParams(int P, bool ParNeeded) @safe
{
    if (ParNeeded)
        Mod.write("(");
    if (EAG.ParamBuf[P].Affixform != EAG.nil)
    {
        if (!ParNeeded)
            Mod.write(", ");
        while (true)
        {
            assert(AffixName[P] >= 0);

            GenVar(AffixName[P]);
            ++P;
            if (EAG.ParamBuf[P].Affixform == EAG.nil)
                break;
            Mod.write(", ");
        }
    }
    if (ParNeeded)
        Mod.write(")");
}

public void GenSynPred(size_t Sym, int P)
{
    int Next;
    int Tree;
    int V;
    bool IsPred = EAG.Pred[Sym];

    if (!UseRefCnt)
        GetAffixSpace(P);
    while (EAG.ParamBuf[P].Affixform != EAG.nil)
    {
        if (!EAG.ParamBuf[P].isDef)
        {
            Tree = EAG.ParamBuf[P].Affixform;
            if (SavePos)
            {
                Mod.write("PopPos(");
                Mod.write(EAG.MAlt[EAG.NodeBuf[Tree]].Arity);
                Mod.write(");\n");
            }
            if (UseConst && AffixPlace[P] >= 0)
            {
                GenVar(AffixName[P]);
                Mod.write(" = ");
                Mod.write(AffixPlace[P]);
                Mod.write(";\n");
                if (UseRefCnt)
                    GenIncRefCnt(-AffixPlace[P], 1);
            }
            else if (Tree < 0)
            {
                V = -Tree;
                if (UseRefCnt && IsPred)
                    GenIncRefCnt(VarName[V], 1);
                if (AffixName[P] != VarName[V])
                {
                    GenVar(AffixName[P]);
                    Mod.write(" = ");
                    GenVar(VarName[V]);
                    Mod.write(";\n");
                }
            }
            else
            {
                if (UseRefCnt)
                {
                    Mod.write("GetHeap(");
                    Mod.write(EAG.MAlt[EAG.NodeBuf[Tree]].Arity);
                    Mod.write(", ");
                    GenVar(NodeName[Tree]);
                    Mod.write("); ");
                    Gen1SynTree(Tree, EmptySet, IsPred);
                    Mod.write("\n");
                }
                else
                {
                    GenVar(AffixName[P]);
                    Mod.write(" = NextHeap; ");
                    Next = 0;
                    GenSynTree(Tree, EmptySet, Next);
                    GenHeapInc(Next);
                }
            }
        }
        ++P;
    }
}

private void GetAffixSpace(int P) @safe
{
    int Heap = 0;

    while (EAG.ParamBuf[P].Affixform != EAG.nil)
    {
        if (!EAG.ParamBuf[P].isDef && (!UseConst || UseConst && AffixPlace[P] < 0))
            Heap += AffixSpace[P];
        ++P;
    }
    GenOverflowGuard(Heap);
}

/**
 * RepVar ist nur im Kontext der Generierung von Repetition-Code zu verstehen
 */
private void GenSynTree(int Node, BitArray RepVar, ref int Next)
{
    int Next1;
    int Node1;
    int V;
    const Alt = EAG.NodeBuf[Node];

    GenHeap(0, Next);
    Mod.write(" = ");
    Mod.write(NodeIdent[Alt]);
    Mod.write("; ");
    Next1 = Next;
    Next += 1 + EAG.MAlt[Alt].Arity;
    for (int n = 1; n <= EAG.MAlt[Alt].Arity; ++n)
    {
        Node1 = EAG.NodeBuf[Node + n];
        if (Node1 < 0)
        {
            V = -Node1;
            if (RepVar[V])
            {
                GenVar(VarName[V]);
                Mod.write(" = NextHeap + ");
                Mod.write(Next1 + n);
            }
            else
            {
                GenHeap(0, Next1 + n);
                Mod.write(" = ");
                GenVar(VarName[V]);
            }
            Mod.write("; ");
        }
        else
        {
            GenHeap(0, Next1 + n);
            Mod.write(" = ");
            if (UseConst && EAG.MAlt[EAG.NodeBuf[Node1]].Arity == 0)
            {
                Mod.write(Leaf[EAG.NodeBuf[Node1]]);
                Mod.write("; ");
            }
            else
            {
                Mod.write("NextHeap + ");
                Mod.write(Next);
                Mod.write("; ");
                GenSynTree(Node1, RepVar, Next);
            }
        }
    }
}

/**
 * RepVar ist nur im Kontext der Generierung von Repetition-Code zu verstehen
 */
private void Gen1SynTree(int Node, BitArray RepVar, bool IsPred)
{
    int Node1;
    int V;

    GenHeap(NodeName[Node], 0);
    Mod.write(" = ");
    Mod.write(NodeIdent[EAG.NodeBuf[Node]]);
    Mod.write("; ");
    for (int n = 1; n <= EAG.MAlt[EAG.NodeBuf[Node]].Arity; ++n)
    {
        Node1 = EAG.NodeBuf[Node + n];
        if (Node1 < 0)
        {
            V = -Node1;
            if (RepVar[V])
            {
                GenVar(VarName[V]);
                Mod.write(" = ");
                GenVar(NodeName[Node]);
                Mod.write(" + ");
                Mod.write(n);
                Mod.write("; ");
            }
            else
            {
                GenHeap(NodeName[Node], n);
                Mod.write(" = ");
                GenVar(VarName[V]);
                Mod.write("; ");
                if (IsPred)
                    GenIncRefCnt(VarName[V], 1);
            }
        }
        else if (EAG.MAlt[EAG.NodeBuf[Node1]].Arity == 0)
        {
            if (UseConst)
            {
                GenHeap(NodeName[Node], n);
                Mod.write(" = ");
                Mod.write(Leaf[EAG.NodeBuf[Node1]]);
                Mod.write("; ");
                GenIncRefCnt(-Leaf[EAG.NodeBuf[Node1]], 1);
            }
            else
            {
                Mod.write("GetHeap(0, ");
                GenHeap(NodeName[Node], n);
                Mod.write("); Heap[");
                GenHeap(NodeName[Node], n);
                Mod.write("] = ");
                Mod.write(NodeIdent[EAG.NodeBuf[Node1]]);
                Mod.write(";");
            }
        }
        else
        {
            Mod.write("GetHeap(");
            Mod.write(EAG.MAlt[EAG.NodeBuf[Node1]].Arity);
            Mod.write(", ");
            if (NodeName[Node] == NodeName[Node1])
            {
                GenHeap(NodeName[Node], n);
                Mod.write("); ");
                GenVar(NodeName[Node1]);
                Mod.write(" = ");
                GenHeap(NodeName[Node], n);
            }
            else
            {
                GenVar(NodeName[Node1]);
                Mod.write("); ");
                GenHeap(NodeName[Node], n);
                Mod.write(" = ");
                GenVar(NodeName[Node1]);
            }
            Mod.write(";\n");
            Gen1SynTree(Node1, RepVar, IsPred);
        }
    }
}

public void GenAnalPred(size_t Sym, int P)
{
    int Node;
    int Tree;
    int n;
    int V;
    int Vn;
    bool MakeRefCnt;
    bool IsPred;

    void Comp()
    {
        if (UseRefCnt)
            Mod.write(".MOD(refConst)");
        if (IsPred)
            Mod.write(" == ");
        else
            Mod.write(" != ");
    }

    void GenEqualErrMsg(size_t Sym, int Var)
    {
        Mod.write(`"'`);
        Mod.write(EAG.VarRepr(Var));
        Mod.write("' failed in '");
        Mod.write(EAG.NamedHNontRepr(Sym));
        Mod.write(`'"`);
    }

    void GenAnalErrMsg(size_t Sym)
    {
        Mod.write(`"`);
        Mod.write(EAG.NamedHNontRepr(Sym));
        Mod.write(`"`);
    }

    void GenEqualPred(int VarName1, int Var2, bool Eq)
    {
        if (IsPred)
        {
            Mod.write("if (");
            if (!Eq)
                Mod.write("!");
            Mod.write("Equal(");
            GenVar(VarName1);
            Mod.write(", ");
            GenVar(VarName[Var2]);
            Mod.write("))\n");
            Mod.write("{\n");
            ++IfLevel;
        }
        else
        {
            if (!Eq)
                Mod.write("Un");
            Mod.write("Eq(");
            GenVar(VarName1);
            Mod.write(", ");
            GenVar(VarName[Var2]);
            Mod.write(", ");
            GenEqualErrMsg(Sym, Var2);
            Mod.write("); ");
        }
    }

    void GenAnalTree(int Node)
    {
        int n;
        int Node1;
        int V;
        int Vn;

        Mod.write("if (");
        GenHeap(NodeName[Node], 0);
        Comp;
        Mod.write(NodeIdent[EAG.NodeBuf[Node]]);
        Mod.write(")");
        if (IsPred)
        {
            Mod.write("\n");
            Mod.write("{\n");
            ++IfLevel;
        }
        else
        {
            Mod.write(" AnalyseError(");
            GenVar(NodeName[Node]);
            Mod.write(", ");
            GenAnalErrMsg(Sym);
            Mod.write(");\n");
        }
        for (n = 1; n <= EAG.MAlt[EAG.NodeBuf[Node]].Arity; ++n)
        {
            Node1 = EAG.NodeBuf[Node + n];
            if (Node1 < 0)
            {
                V = -Node1;
                if (EAG.Var[V].Def)
                {
                    if (IsPred)
                    {
                        Mod.write("if (Equal(");
                        GenHeap(NodeName[Node], n);
                        Mod.write(", ");
                        GenVar(VarName[V]);
                        Mod.write("))\n");
                        Mod.write("{\n");
                        ++IfLevel;
                    }
                    else
                    {
                        Mod.write("Eq(");
                        GenHeap(NodeName[Node], n);
                        Mod.write(", ");
                        GenVar(VarName[V]);
                        Mod.write(", ");
                        GenEqualErrMsg(Sym, V);
                        Mod.write("); ");
                    }
                }
                else
                {
                    EAG.Var[V].Def = true;
                    GenVar(VarName[V]);
                    Mod.write(" = ");
                    GenHeap(NodeName[Node], n);
                    Mod.write("; ");
                    if (EAG.Var[EAG.Var[V].Neg].Def)
                    {
                        Vn = EAG.Var[V].Neg;
                        GenEqualPred(VarName[Vn], V, false);
                        if (MakeRefCnt)
                        {
                            if (VarDepPos[Vn] == P)
                            {
                                GenFreeHeap(VarName[Vn]);
                                VarDepPos[Vn] = -2;
                            }
                        }
                    }
                    if (MakeRefCnt && VarRefCnt[V] > 0)
                        GenIncRefCnt(VarName[V], VarRefCnt[V]);
                }
                if (MakeRefCnt)
                {
                    if (VarDepPos[V] == P)
                    {
                        GenFreeHeap(VarName[V]);
                        VarDepPos[V] = -2;
                    }
                }
            }
            else
            {
                if (EAG.MAlt[EAG.NodeBuf[Node1]].Arity == 0)
                {
                    if (UseConst)
                    {
                        Mod.write("if (");
                        GenHeap(NodeName[Node], n);
                        Comp;
                        Mod.write(Leaf[EAG.NodeBuf[Node1]]);
                    }
                    else
                    {
                        Mod.write("if (Heap[");
                        GenHeap(NodeName[Node], n);
                        Mod.write("]");
                        Comp;
                        Mod.write(NodeIdent[EAG.NodeBuf[Node1]]);
                    }
                    Mod.write(")");
                    if (IsPred)
                    {
                        Mod.write("\n");
                        Mod.write("{\n");
                        ++IfLevel;
                    }
                    else
                    {
                        Mod.write(" AnalyseError(");
                        GenHeap(NodeName[Node], n);
                        Mod.write(", ");
                        GenAnalErrMsg(Sym);
                        Mod.write(");");
                    }
                    Mod.write("\n");
                }
                else
                {
                    GenVar(NodeName[Node1]);
                    Mod.write(" = ");
                    GenHeap(NodeName[Node], n);
                    Mod.write("; ");
                    GenAnalTree(Node1);
                }
            }
        }
    }

    IsPred = EAG.Pred[Sym];
    IfLevel = 0;
    MakeRefCnt = UseRefCnt && !IsPred;
    while (EAG.ParamBuf[P].Affixform != EAG.nil)
    {
        if (EAG.ParamBuf[P].isDef)
        {
            Tree = EAG.ParamBuf[P].Affixform;
            if (Tree < 0)
            {
                V = -Tree;
                if (EAG.Var[V].Def)
                {
                    assert(AffixName[P] != VarName[V]);

                    GenEqualPred(AffixName[P], V, true);
                    if (MakeRefCnt)
                        GenFreeHeap(AffixName[P]);
                }
                else
                {
                    EAG.Var[V].Def = true;
                    if (AffixName[P] != VarName[V])
                    {
                        GenVar(VarName[V]);
                        Mod.write(" = ");
                        GenVar(AffixName[P]);
                        Mod.write(";\n");
                    }
                    if (EAG.Var[EAG.Var[V].Neg].Def)
                    {
                        Vn = EAG.Var[V].Neg;
                        GenEqualPred(VarName[Vn], V, false);
                        if (MakeRefCnt)
                        {
                            if (VarDepPos[Vn] == P)
                            {
                                GenFreeHeap(VarName[Vn]);
                                VarDepPos[Vn] = -2;
                            }
                        }
                    }
                    if (MakeRefCnt)
                    {
                        if (VarRefCnt[V] > 1)
                            GenIncRefCnt(VarName[V], VarRefCnt[V] - 1);
                        else if (VarRefCnt[V] == 0)
                            GenFreeHeap(AffixName[P]);
                    }
                }
                if (MakeRefCnt)
                {
                    if (VarDepPos[V] == P)
                    {
                        GenFreeHeap(VarName[V]);
                        VarDepPos[V] = -2;
                    }
                }
            }
            else
            {
                if (EAG.MAlt[EAG.NodeBuf[Tree]].Arity == 0)
                {
                    Mod.write("if (");
                    GenHeap(AffixName[P], 0);
                    Comp;
                    Mod.write(NodeIdent[EAG.NodeBuf[Tree]]);
                    Mod.write(")");
                    if (IsPred)
                    {
                        Mod.write("\n");
                        Mod.write("{\n");
                        ++IfLevel;
                    }
                    else
                    {
                        Mod.write(" AnalyseError(");
                        GenVar(AffixName[P]);
                        Mod.write(", ");
                        GenAnalErrMsg(Sym);
                        Mod.write(");");
                    }
                    Mod.write("\n");
                }
                else
                {
                    GenAnalTree(Tree);
                }
                if (MakeRefCnt)
                    GenFreeHeap(AffixName[P]);
            }
        }
        ++P;
    }
    if (SavePos)
        Mod.write("PushPos;\n");
}

private void GenHeap(int Var, int Offset) @safe
{
    Mod.write("Heap[");
    if (Var <= 0)
        Mod.write("NextHeap");
    else
        GenVar(Var);
    if (Offset > 0)
    {
        Mod.write(" + ");
        Mod.write(Offset);
    }
    else if (Offset < 0)
    {
        Mod.write(" - ");
        Mod.write(-Offset);
    }
    Mod.write("]");
}

private void GenIncRefCnt(int Var, int n) @safe
{
    Mod.write("Heap[");
    if (Var < 0)
        Mod.write(-Var);
    else
        GenVar(Var);
    Mod.write("] += ");
    if (n != 1)
    {
        Mod.write(n);
        Mod.write(" * ");
    }
    Mod.write("refConst;\n");
}

private void GenOverflowGuard(int n) @safe
{
    if (n > 0)
    {
        Mod.write("if (NextHeap >= Heap.length - ");
        Mod.write(n);
        Mod.write(") EvalExpand;\n");
    }
}

private void GenFreeHeap(int Var) @safe
{
    Mod.write("FreeHeap(");
    GenVar(Var);
    Mod.write(");\n");
}

private void GenHeapInc(int n) @safe
{
    if (n != 0)
    {
        if (n == 1)
        {
            Mod.write("++NextHeap;\n");
        }
        else
        {
            Mod.write("NextHeap += ");
            Mod.write(n);
            Mod.write(";\n");
        }
    }
}

private void GenVar(int Var) @safe
{
    Mod.write("V");
    Mod.write(Var);
}

static this() @nogc nothrow @safe
{
    Testing = false;
    Generating = false;
}
