
require(GetScriptDirectory() ..  "/thd2_item_purchase")


local tableItemsToBuy = {
				--扫把+补刀斧转河童手枪
				"item_broom",
				"item_quelling_blade",

				"item_knife",
				"item_wind_amulet",

				--月兔幻觉兵器
				"item_violin",
				"item_screw_driver",
					"item_recipe_inaba_illusion_weapon",

				--隙间鞋
					"item_recipe_travel_boots",

				"item_mushroom",
				"item_mushroom",
					"item_recipe_touhou_banana",
				"item_knife",
				"item_scissors",
					"item_recipe_quant",
					"item_recipe_anchor",

				"item_aunt_clothes",
				"item_aunt_clothes",
				"item_cat_ear",
				"item_cat_foot",
					"item_recipe_yuemianzhinu",
				"item_cake",
				"item_rocket_diagram",
					"item_recipe_hetongtuijinzhuangzhi",
					"item_recipe_yuemianjidongzhuangzhi",

				"item_cat_foot",
				"item_paper_mask",
				"item_rocket_diagram",
				"item_zun_hat",
					"item_recipe_wanbaochui",
					"item_recipe_wanbaochui2",

				"item_silver_knife",
				"item_paper_mask",
				"item_cat_foot",
					"item_recipe_ganggenier",

				"item_god_hand",
				"item_god_hand",
					"item_recipe_loneliness",

			};


----------------------------------------------------------------------------------------------------

local seed_id = nil

function ItemPurchaseThink()
	if seed_id == nil then
		seed_id = RandomInt(1,999999999)
	end
	ConsiderItemPurchase(tableItemsToBuy,seed_id)
end

----------------------------------------------------------------------------------------------------
