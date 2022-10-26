module epsilon.soag.soag;

import EAG = epsilon.eag;
import Predicates = epsilon.predicates;
import runtime;
import std.bitmanip : BitArray;

const firstSym = EAG.firstHNont;
const firstRule = 0;
const firstSymOcc = 0;
const firstAffOcc = 0;
const firstPartNum = 0;
const firstAffOccNum = 0;
const firstVS = 1;
const firstDefAffOcc = EAG.firstVar;
const firstStorageName = 0;
const firstAffixApplCnt = EAG.firstVar;
const nil = -1;

struct SymDesc
{
    int FirstOcc;
    int MaxPart;
    EAG.ScopeDesc AffPos;

    public string toString() const pure @safe
    {
        import std.format : format;

        string[] items;

        items ~= format!"FirstOcc=%s"(FirstOcc);
        items ~= format!"MaxPart=%s"(MaxPart);
        items ~= format!"AffPos=%s"(AffPos);
        return format!"Sym(%-(%s, %))"(items);
    }
}

class RuleDesc
{
    EAG.ScopeDesc SymOcc;
    EAG.ScopeDesc AffOcc;
    BitArray[] TDP;
    BitArray[] DP;
    EAG.ScopeDesc VS;
}

alias RuleBase = RuleDesc;

class EmptyRule : RuleDesc
{
    EAG.Rule Rule;
}

class OrdRule : RuleDesc
{
    EAG.Alt Alt;
}

struct SymOccDesc
{
    int SymInd;
    int RuleInd;
    EAG.Nont Nont;
    EAG.ScopeDesc AffOcc;
    int Next;

    public string toString() const @safe
    {
        import std.format : format;

        string[] items;

        items ~= EAG.HNontRepr(SymInd);
        items ~= format!"RuleInd=%s"(RuleInd);
        items ~= format!"Nont=%s"(Nont);
        items ~= format!"AffOcc=%s"(AffOcc);
        items ~= format!"Next=%s"(Next);
        return format!"SymOcc(%-(%s, %))"(items);
    }
}

struct AffOccNumRecord
{
    int InRule;
    int InSym;

    public string toString() const pure @safe
    {
        import std.format : format;

        string[] items;

        items ~= format!"InRule=%s"(InRule);
        items ~= format!"InSym=%s"(InSym);
        return format!"AffOccNum(%-(%s, %))"(items);
    }
}

struct AffOccDesc
{
    int ParamBufInd;
    int SymOccInd;
    AffOccNumRecord AffOccNum;

    public string toString() const pure @safe
    {
        import std.format : format;

        string[] items;

        items ~= format!"ParamBufInd=%s"(ParamBufInd);
        items ~= format!"SymOccInd=%s"(SymOccInd);
        items ~= AffOccNum.toString;
        return format!"AffOcc(%-(%s, %))"(items);
    }
}

class Instruction
{
}

class Visit : Instruction
{
    int SymOcc;
    int VisitNo;
}

class Leave : Instruction
{
    int VisitNo;
}

class Call : Instruction
{
    int SymOcc;
}

SymDesc[] Sym;
int[] PartNum;
RuleBase[] Rule;
SymOccDesc[] SymOcc;
AffOccDesc[] AffOcc;
Instruction[] VS;
int[] DefAffOcc;
int[] StorageName;
int[] AffixApplCnt;
int NextSym;
int NextPartNum;
int NextRule;
int NextSymOcc;
int NextAffOcc;
int NextVS;
int NextDefAffOcc;
int NextStorageName;
int NextAffixApplCnt;
int MaxAffNumInRule;
int MaxAffNumInSym;
int MaxPart;
const abnormalError = 1;
const cyclicTDP = 2;
const notLeftDefined = 3;
const notEnoughMemory = 99;

void Error(T)(int ErrorType, T Proc)
{
    import std.stdio : stdout;  // TODO: replace with log

    stdout.write("ERROR: ");
    switch (ErrorType)
    {
    case abnormalError:
        stdout.write("abnormal error ");
        break;
    case notEnoughMemory:
        stdout.write("memory allocation failed ");
        break;
    case cyclicTDP:
        stdout.write("TDP is cyclic...aborted\n");
        break;
    case notLeftDefined:
        stdout.write("Grammar are not left defined\n");
        break;
    default:
        assert(0);
    }
    if (ErrorType == abnormalError || ErrorType == notEnoughMemory)
    {
        stdout.write("in procedure ");
        stdout.writeln(Proc);
    }
    throw new Exception("TODO");
}

void Expand() nothrow @safe
{
    size_t NewLen(size_t ArrayLen)
    {
        assert(ArrayLen < DIV(size_t.max, 2));

        return 2 * ArrayLen + 1;
    }

    if (NextAffOcc >= AffOcc.length)
    {
        auto AffOcc1 = new AffOccDesc[NewLen(AffOcc.length)];

        for (size_t i = firstAffOcc; i < AffOcc.length; ++i)
            AffOcc1[i] = AffOcc[i];
        AffOcc = AffOcc1;
    }
    if (NextSymOcc >= SymOcc.length)
    {
        auto SymOcc1 = new SymOccDesc[NewLen(SymOcc.length)];

        for (size_t i = firstSymOcc; i < SymOcc.length; ++i)
            SymOcc1[i] = SymOcc[i];
        SymOcc = SymOcc1;
    }
    if (NextRule >= Rule.length)
    {
        auto Rule1 = new RuleBase[NewLen(Rule.length)];

        for (size_t i = firstRule; i < Rule.length; ++i)
            Rule1[i] = Rule[i];
        Rule = Rule1;
    }
    if (NextVS >= VS.length)
    {
        auto VS1 = new Instruction[NewLen(VS.length)];

        for (size_t i = firstVS; i < VS.length; ++i)
            VS1[i] = VS[i];
        VS = VS1;
    }
}

void AppAffOcc(int Params) nothrow @safe
{
    if (Params != EAG.empty)
    {
        while (EAG.ParamBuf[Params].Affixform != EAG.nil)
        {
            AffOcc[NextAffOcc].ParamBufInd = Params;
            AffOcc[NextAffOcc].SymOccInd = NextSymOcc;
            AffOcc[NextAffOcc].AffOccNum.InRule = NextAffOcc - Rule[NextRule].AffOcc.Beg;
            AffOcc[NextAffOcc].AffOccNum.InSym = NextAffOcc - SymOcc[NextSymOcc].AffOcc.Beg;
            ++NextAffOcc;
            if (NextAffOcc >= AffOcc.length)
                Expand;
            ++Params;
        }
    }
}

void AppSymOccs(EAG.Factor Factor) nothrow @safe
{
    while (Factor !is null)
    {
        if (auto nont = cast(EAG.Nont) Factor)
        {
            SymOcc[NextSymOcc].SymInd = nont.Sym;
            SymOcc[NextSymOcc].RuleInd = NextRule;
            SymOcc[NextSymOcc].Nont = nont;
            SymOcc[NextSymOcc].AffOcc.Beg = NextAffOcc;
            AppAffOcc(nont.Actual.Params);
            SymOcc[NextSymOcc].AffOcc.End = NextAffOcc - 1;
            SymOcc[NextSymOcc].Next = Sym[nont.Sym].FirstOcc;
            Sym[nont.Sym].FirstOcc = NextSymOcc;
            ++NextSymOcc;
            if (NextSymOcc >= SymOcc.length)
                Expand;
        }
        Factor = Factor.Next;
    }
}

void AppLeftSymOcc(size_t leftSym, int Params) @safe
{
    import std.conv : to;

    SymOcc[NextSymOcc].SymInd = leftSym.to!int;
    SymOcc[NextSymOcc].RuleInd = NextRule;
    SymOcc[NextSymOcc].Nont = null;
    SymOcc[NextSymOcc].AffOcc.Beg = NextAffOcc;
    AppAffOcc(Params);
    SymOcc[NextSymOcc].AffOcc.End = NextAffOcc - 1;
    SymOcc[NextSymOcc].Next = Sym[leftSym].FirstOcc;
    Sym[leftSym].FirstOcc = NextSymOcc;
    ++NextSymOcc;
    if (NextSymOcc >= SymOcc.length)
        Expand;
}

void AppEmptyRule(size_t leftSym, EAG.Rule EAGRule) @safe
{
    EmptyRule A = new EmptyRule;

    Rule[NextRule] = A;
    A.Rule = EAGRule;
    A.SymOcc.Beg = NextSymOcc;
    A.AffOcc.Beg = NextAffOcc;
    if (auto opt = cast(EAG.Opt) EAGRule)
        AppLeftSymOcc(leftSym, opt.Formal.Params);
    else if (auto rep = cast(EAG.Rep) EAGRule)
        AppLeftSymOcc(leftSym, rep.Formal.Params);
    A.SymOcc.End = NextSymOcc - 1;
    A.AffOcc.End = NextAffOcc - 1;
    ++NextRule;
    if (NextRule >= Rule.length)
        Expand;
}

void AppRule(EAG.Alt EAGAlt) @safe
{
    OrdRule A = new OrdRule;

    Rule[NextRule] = A;
    A.Alt = EAGAlt;
    A.SymOcc.Beg = NextSymOcc;
    A.AffOcc.Beg = NextAffOcc;
    AppLeftSymOcc(EAGAlt.Up, EAGAlt.Formal.Params);
    AppSymOccs(EAGAlt.Sub);
    A.SymOcc.End = NextSymOcc - 1;
    A.AffOcc.End = NextAffOcc - 1;
    ++NextRule;
    if (NextRule >= Rule.length)
        Expand;
}

void AppRepRule(EAG.Alt EAGAlt) @safe
{
    OrdRule A = new OrdRule;

    Rule[NextRule] = A;
    A.Alt = EAGAlt;
    A.SymOcc.Beg = NextSymOcc;
    A.AffOcc.Beg = NextAffOcc;
    AppLeftSymOcc(EAGAlt.Up, EAGAlt.Formal.Params);
    AppSymOccs(EAGAlt.Sub);
    AppLeftSymOcc(EAGAlt.Up, EAGAlt.Actual.Params);
    A.SymOcc.End = NextSymOcc - 1;
    A.AffOcc.End = NextAffOcc - 1;
    ++NextRule;
    if (NextRule >= Rule.length)
        Expand;
}
/**
 * IN:  Instruktion
 * OUT: -
 * SEM: fügt eine Instruktion in die Datenstruktur VS ein
 */
void AppVS(ref Instruction I) nothrow @safe
{
    VS[NextVS] = I;
    ++NextVS;
    if (NextVS >= VS.length)
        Expand;
}

/**
 * IN:  Symbol, Nummer des Affixposition
 * OUT: boolscher Wert
 * SEM: Test, ob Affixposition inherited ist
 */
bool IsInherited(int S, int AffOccNum) @nogc nothrow @safe
{
    return EAG.DomBuf[EAG.HNont[S].Sig + AffOccNum] < 0;
}

/**
 * IN:  Symbol, Nummer des Affixposition
 * OUT: boolscher Wert
 * SEM: Test, ob Affixposition synthesized ist
 */
bool IsSynthesized(size_t S, int AffOccNum) @nogc nothrow @safe
{
    return EAG.DomBuf[EAG.HNont[S].Sig + AffOccNum] > 0;
}

/**
 * IN:  Symbol, Nummern zweier Affixpositionen zum Symbol
 * OUT: boolscher Wert
 * SEM: Test, ob die beiden Affixpositionen orientierbar sind
 */
bool IsOrientable(int S, int AffOccNum1, int AffOccNum2) @nogc nothrow @safe
{
    return IsInherited(S, AffOccNum1) && IsSynthesized(S, AffOccNum2)
        || IsInherited(S, AffOccNum2) && IsSynthesized(S, AffOccNum1);
}

/**
 * IN:  Regel
 * OUT: boolscher Wert
 * SEM: Test, ob eine Evaluatorregel vorliegt
 * PRECOND: Predicates.Check muss vorher ausgewertet sein
 */
bool IsEvaluatorRule(size_t R) @nogc nothrow
{
    return !EAG.Pred[SymOcc[Rule[R].SymOcc.Beg].SymInd];
}

/**
 * IN:  Symbolvorkommen
 * OUT: boolscher Wert
 * SEM: Test, ob ein Prädikat vorliegt
 * PRECOND: Predicates.Check muss vorher ausgewertet sein
 */
bool IsPredNont(int SO) @nogc nothrow
{
    return EAG.Pred[SymOcc[SO].SymInd];
}

/**
 * IN:  zwei Instruktionen aus der Visit-Sequenz
 * OUT: boolscher Wert
 * SEM: Test, ob zwei Instruktionnen gleich sind;
 *      etwas optimiert für den Fall, dass einer oder beide Parameter nil ist
 */
bool isEqual(Instruction I1, Instruction I2) @nogc nothrow pure @safe
{
    if (I1 is null && I2 is null)
        return true;
    else if (I1 is null || I2 is null)
        return false;
    else if (cast(Visit) I1 !is null && cast(Visit) I2 !is null)
        return (cast(Visit) I1).SymOcc == (cast(Visit) I2).SymOcc
            && (cast(Visit) I1).VisitNo == (cast(Visit) I2).VisitNo;
    else if (cast(Leave) I1 !is null && cast(Leave) I2 !is null)
        return (cast(Leave) I1).VisitNo == (cast(Leave) I2).VisitNo;
    else if (cast(Call) I1 !is null && cast(Call) I2 !is null)
        return (cast(Call) I1).SymOcc == (cast(Call) I2).SymOcc;
    else
        return false;
}

/**
 * SEM: Initialisierung der SOAG-Datenstruktur; Transformation der EAG-Datenstruktur
 */
void Init()
{
    EAG.Alt A;
    int a;
    int Max;

    Sym = new SymDesc[EAG.NextHNont];
    Rule = new RuleBase[128];
    SymOcc = new SymOccDesc[256];
    AffOcc = new AffOccDesc[512];
    VS = new Instruction[512];
    DefAffOcc = new int[EAG.NextVar];
    AffixApplCnt = new int[EAG.NextVar];
    StorageName = null;
    NextSym = EAG.NextHNont;
    NextRule = firstRule;
    NextSymOcc = firstSymOcc;
    NextAffOcc = firstAffOcc;
    NextVS = firstVS;
    NextDefAffOcc = EAG.NextVar;
    NextStorageName = nil;
    NextAffixApplCnt = EAG.NextVar;
    Predicates.Check;
    for (size_t i = EAG.firstHNont; i < EAG.NextHNont; ++i)
        Sym[i].FirstOcc = nil;
    foreach (i; EAG.All.bitsSet)
    {
        if (cast(EAG.Rep) EAG.HNont[i].Def)
        {
            A = EAG.HNont[i].Def.Sub;
            while (A !is null)
            {
                AppRepRule(A);
                A = A.Next;
            }
        }
        else
        {
            A = EAG.HNont[i].Def.Sub;
            while (A !is null)
            {
                AppRule(A);
                A = A.Next;
            }
        }
        if (cast(EAG.Rep) EAG.HNont[i].Def || cast(EAG.Opt) EAG.HNont[i].Def)
            AppEmptyRule(i, EAG.HNont[i].Def);
    }
    MaxAffNumInRule = 0;
    for (size_t i = firstRule; i < NextRule; ++i)
    {
        Max = Rule[i].AffOcc.End - Rule[i].AffOcc.Beg;
        if (Max > MaxAffNumInRule)
            MaxAffNumInRule = Max;
        if (IsEvaluatorRule(i) && Max >= 0)
        {
            Rule[i].TDP = new BitArray[Max + 1];
            Rule[i].DP = new BitArray[Max + 1];
            for (a = firstAffOccNum; a <= Max; ++a)
            {
                Rule[i].TDP[a] = BitArray();
                Rule[i].TDP[a].length = Max + 1 + 1;
                Rule[i].DP[a] = BitArray();
                Rule[i].DP[a].length = Max + 1 + 1;
            }
        }
    }
    MaxAffNumInSym = 0;
    NextPartNum = firstPartNum;
    foreach (i; EAG.All.bitsSet)
    {
        Max = SymOcc[Sym[i].FirstOcc].AffOcc.End - SymOcc[Sym[i].FirstOcc].AffOcc.Beg;
        Sym[i].AffPos.Beg = NextPartNum;
        NextPartNum = NextPartNum + Max;
        Sym[i].AffPos.End = NextPartNum;
        ++NextPartNum;
        if (Max > MaxAffNumInSym)
            MaxAffNumInSym = Max;
        Sym[i].MaxPart = 0;
    }
    PartNum = new int[NextPartNum];
    MaxPart = 0;
    for (size_t i = EAG.firstVar; i < EAG.NextVar; ++i)
    {
        DefAffOcc[i] = -1;
        AffixApplCnt[i] = 0;
    }
}

static this() @safe
{
    import log : info;

    info!"SOAG-Evaluatorgenerator 1.06 dk 14.03.98";
}
