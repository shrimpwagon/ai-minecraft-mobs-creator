package com.aicreator.aitemplate;

import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.CreativeModeTab;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Creative-mode tab for this mod. As assets get added, append
 * {@code output.accept(ModBlocks.X.get())} / {@code ModItems.Y.get()} lines
 * inside {@code displayItems()}. Tab icon defaults to a barrier until you
 * have a real signature asset to swap in.
 */
public final class ModCreativeTab {
    public static final DeferredRegister<CreativeModeTab> CREATIVE_MODE_TABS =
            DeferredRegister.create(Registries.CREATIVE_MODE_TAB, MyFirstMod.MODID);

    public static final DeferredHolder<CreativeModeTab, CreativeModeTab> CUSTOM_TAB =
            CREATIVE_MODE_TABS.register("custom", () -> CreativeModeTab.builder()
                    .title(Component.translatable("itemGroup.aitemplate.custom"))
                    .icon(() -> new ItemStack(Items.BARRIER))
                    .displayItems((params, output) -> {
                        // Append entries here as new blocks / items / spawn eggs are added.
                    })
                    .build()
            );

    private ModCreativeTab() {}
}
