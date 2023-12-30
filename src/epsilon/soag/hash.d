module epsilon.soag.hash;

import SOAG = epsilon.soag.soag;
import runtime;

class HashEntry
{
    SOAG.Instruction Instr;
}

HashEntry[] HashTab;
int MaxHashTabIndex;
int V4711;
int V711;

/**
 * SEM: leert die Hash-Tabelle
 */
void Reset() @nogc nothrow @safe
{
    for (int i = 0; i < MaxHashTabIndex; ++i)
        HashTab[i] = null;
}

/**
 * IN:  maximale Anzahl an Affixparametern in einer Regel
 * OUT: -
 * SEM: reserviert Speicher für die Hash-Tabelle und setzt die max. Hash-Adresse
 */
void Init(int MaxAffInRule) @safe
in (MaxAffInRule > 0)
{
    import std.conv : to;
    import std.math : log2;

    int Exp;
    int i;
    // Exp = SHORT(ENTIER(Math.ln(MaxAffInRule) / Math.ln(2)) + 1);
    Exp = log2(MaxAffInRule.to!double).to!int + 1;
    MaxHashTabIndex = 2;
    for (i = 2; i <= Exp; ++i)
        MaxHashTabIndex = MaxHashTabIndex * 2;
    HashTab = new HashEntry[MaxHashTabIndex];
    Reset;
}

/**
 * IN:  Instruktion aus der Visit-Sequenz, kein NIL !
 * OUT: Index in der Hash-Tabelle
 * SEM: Ermittlung Indexes in der Hash-Tabelle
 */
int HashIndex(ref SOAG.Instruction I) @safe
{
    import std.conv : to;

    int Index;
    int Index0;
    int Try;
    bool found;

    /**
     * Fehler im Compiler: kann keine Integerkonstanten > 128 in Multiplikationen verarbeiten
     * IN:  Instruktion
     * OUT: -
     * SEM: Realisierung der Hash-Funktion
     */
    int HashFun(ref SOAG.Instruction I)
    {
        import std.conv : to;

        int Index;

        if (auto visit = cast(SOAG.Visit) I)
            Index = 100 + V4711 * visit.SymOcc + V711 * visit.VisitNo;
        else if (auto leave = cast(SOAG.Leave) I)
            Index = 200 + V4711 * leave.VisitNo;
        else if (auto call = cast(SOAG.Call) I)
            Index = 300 + V4711 * call.SymOcc;
        else
            Index = 0;
        return MOD(Index, MaxHashTabIndex).to!int;
    }

    Try = 0;
    Index0 = HashFun(I);
    Index = Index0;
    if (HashTab[Index] is null)
    {
        found = true;
    }
    else
    {
        found = SOAG.isEqual(I, HashTab[Index].Instr);
    }
    while (!found)
    {
        ++Try;
        Index = MOD(Index0 - Try * (DIV(Index0, 2) * 2 + 1), MaxHashTabIndex).to!int;
        if (HashTab[Index] is null)
        {
            found = true;
        }
        else
        {
            found = SOAG.isEqual(I, HashTab[Index].Instr);
        }
    }
    return Index;
}

/**
 * IN:  Instruktion aus der Visit-Sequenz
 * OUT: boolscher Wert
 * SEM: Test, ob die Instruktion schon in der Hash-Tabelle enthalten ist
 */
bool IsIn(SOAG.Instruction I) @safe
{
    if (I is null)
        return true;

    const Index = HashIndex(I);

    return HashTab[Index] !is null;
}

/**
 * IN:  Instruktion der Visit-Sequenz
 * OUT: -
 * SEM: fügt die Instruktion in die Hash-Tabelle ein
 */
void Enter(SOAG.Instruction I) @safe
{
    if (I !is null)
    {
        int Index = HashIndex(I);
        HashEntry Entry = new HashEntry;

        Entry.Instr = I;
        HashTab[Index] = Entry;
    }
}

static this() @nogc nothrow @safe
{
    V4711 = 4711;
    V711 = 711;
}
