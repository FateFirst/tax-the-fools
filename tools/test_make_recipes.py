import importlib.util
import os
import unittest

spec = importlib.util.spec_from_file_location("mk", os.path.join(os.path.dirname(os.path.abspath(__file__)), "make-recipes.py"))
mk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mk)

HEAD = '''local lib = LibCraftsGetLibrary()
local name, version = "Professions-Tailoring", 4
local module = --[[---@type LcProfessionModule]] lib:RegisterProfessionModule(name, version, "Tailoring")
if not module then return end

local Quality = lib.constants.qualities
local SpellSource = lib.constants.spell_sources
local RecipeSource = lib.constants.recipe_sources
'''

FIX = HEAD + '''
module:NewCraft(3854, "Azure \\"Silk\\" Gloves", 145, {SpellSource.Trainer, SpellSource.Trainer})
    :SetResult(4319)
    :AddRecipe(7114, Quality.Common, {RecipeSource.Vendor})
    :AddReagent(2321, 2) -- Fine Thread
    :AddReagent(4234, 2) -- Heavy Leather
    :Save()

module:NewCraft(100, "Dropper", 50, {})
    :SetResult(200)
    :AddRecipe(300, Quality.Rare, {RecipeSource.Drop, RecipeSource.Chest, RecipeSource.Drop, RecipeSource.Fishing})
    :AddRecipe(301, Quality.Rare, {RecipeSource.Quest})
    :AddReagent(1, 1)
    :Save()

module:NewCraft(400, "Changed", 50, {SpellSource.Trainer})
    :SetResult(401)
    :AddReagent(2, 9)
    :Save()

module:NewCraft(7, "Enchanty", 1, {SpellSource.Trainer})
    :AddReagent(9, 1)
    :Save()

if lib.env.is_turtle_wow then
    module:NewCraft(83, "Turtle Gloves", 185, {})
        :SetResult(58134)
        :AddRecipe(75, Quality.Rare, {RecipeSource.Drop})
        :AddRecipe(76, Quality.Rare, {RecipeSource.Drop})
        :AddReagent(3824, 3) -- Shadow Oil
        :Save()
    module:NewCraft(400, "Changed", 50, {})
        :SetResult(401)
        :AddReagent(2, 5)
        :Save()
end
'''


class T(unittest.TestCase):
    def test_parse(self):
        c = mk.parse(FIX)
        self.assertEqual(sorted(c), [83, 100, 400, 3854])  # 7 has no result
        a = c[3854]
        self.assertEqual((a["n"], a["skill"], a["item"], a["pat"], a["r"]), ('Azure "Silk" Gloves', 145, 4319, [7114], [2321, 2, 4234, 2]))
        self.assertFalse(a["turtle"])
        self.assertTrue(c[83]["turtle"])
        self.assertEqual(c[100]["pat"], [300, 301])
        self.assertEqual(c[83]["pat"], [75, 76])
        self.assertEqual(c[400]["r"], [2, 5])  # the turtle block overrides the vanilla craft
        self.assertTrue(c[400]["turtle"])

    def test_render(self):
        out = mk.render("Tailoring", mk.parse(FIX), "URL")
        self.assertIn('t[3854] = { n = "Azure \\"Silk\\" Gloves", skill = 145, item = 4319, pat = { 7114 }, src = { "trainer", "vendor" }, r = { 2321, 2, 4234, 2 } }', out)
        self.assertIn('src = { "drop", "quest", "other" }', out)
        self.assertIn("turtle = true", out)
        self.assertEqual(out.count("turtle = true"), 2)
        self.assertLess(out.index("t[83]"), out.index("t[100]"))
        self.assertLess(out.index("t[100]"), out.index("t[3854]"))
        self.assertEqual(out, mk.render("Tailoring", mk.parse(FIX), "URL"))

    def test_malformed(self):
        for bad in (FIX + "\nmodule:NewCraft(1, \"X\", 1, {})\n    :Frobnicate(3)\n    :Save()\n",
                    FIX + "\nmodule:NewCraft(1, \"X\", 1, {})\n    :SetResult(2)\n",
                    FIX + "\nmodule:NewCraft(1, \"X\", 1, {SpellSource.Nope})\n    :Save()\n",
                    FIX + "\nrandom junk\n"):
            with self.assertRaises(mk.ParseError):
                mk.parse(bad)

    def test_duplicate_outside_turtle_fails(self):
        dup = HEAD + 'module:NewCraft(1, "A", 1, {})\n:SetResult(2)\n:Save()\nmodule:NewCraft(1, "A", 1, {})\n:SetResult(2)\n:Save()\n'
        with self.assertRaises(mk.ParseError):
            mk.parse(dup)

    def test_error_names_line(self):
        try:
            mk.parse(HEAD + "bogus\n")
        except mk.ParseError as e:
            self.assertIn("line 9", str(e))
        else:
            self.fail("no error")


if __name__ == "__main__":
    unittest.main()
