
require(GetScriptDirectory() ..  "/thd2_item_purchase")

local tableItemsToBuy = {}

if RandomInt(1,100) > 70 then
	tableItemsToBuy = {
				"item_broom",
				"item_wind_amulet",
				"item_recipe_horse_red",

				"item_knife",
				"item_rocket_diagram",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",

				"item_violin",
				"item_rocket_diagram",
				"item_juice",
				"item_recipe_grudge_bow",
				"item_gran_grimoire",
				"item_recipe_nuetrident",

				"item_hammer",
				"item_cat_ear",
				"item_cherry_leaf",
				"item_recipe_tentacle",

				"item_horse_king_compressor",
				"item_recipe_horse_king",

				"item_frog",
				"item_juice",
				"item_magic_guide_book",
				"item_recipe_eyunzhifu",
				"item_recipe_morenjingjuan",

				"item_silver_knife",
				"item_paper_mask",
				"item_cat_foot",
				"item_recipe_ganggenier",

				"item_gran_grimoire",
				"item_gran_grimoire",
					"item_recipe_bagua",

			}
else
	tableItemsToBuy = {
				"item_broom",
				"item_wind_amulet",
				"item_recipe_horse_red",

				"item_knife",
				"item_rocket_diagram",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",
					"item_recipe_rocket",

				"item_wind_amulet",
				"item_magic_guide_book",
					"item_recipe_doctor_doll",
				"item_wind_amulet",
				"item_wind_amulet",
					"item_recipe_luna_chip",
				"item_knife",
				"item_rocket_diagram",
					"item_recipe_moon_bow",

				"item_horse_king_compressor",
				"item_recipe_horse_king",

				"item_gran_grimoire",
				"item_gran_grimoire",
					"item_recipe_bagua",

				"item_magic_guide_book",
				"item_gran_grimoire",
				"item_sake",
					"item_recipe_yukkuri_stick",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
					"item_recipe_wanbaochui2",

				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",

			}
end


----------------------------------------------------------------------------------------------------

local seed_id = nil
local next_purchase = -1

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	local npcBot = GetBot()
	local randIndex = RandomInt(2,3)
	local tableEdible = {"item_mushroom_pie_immediate","item_mushroom_kebab_immediate","item_mushroom_soup_immediate"}
	if DotaTime() > 0 and next_purchase > 0 and #tableItemsToBuy < next_purchase then
		table.insert(tableItemsToBuy,tableEdible[randIndex])
	end
	next_purchase = ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
