using System;
using System.Collections.Generic;
using System.Linq;

public static class IndependentGame
{
    public static int Run()
    {
        var stats = new Dictionary<string, object> { ["money"] = 40, ["flag"] = false };
        var values = Enumerable.Range(1, 3).Select(x => x * 2).ToArray();
        if ((bool)stats["flag"] || values.Sum() != 12) throw new Exception("IL state failed");
        stats["money"] = (int)stats["money"] + 1;
        return (int)stats["money"];
    }
}
