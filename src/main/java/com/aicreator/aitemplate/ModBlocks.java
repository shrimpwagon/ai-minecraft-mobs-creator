package com.aicreator.aitemplate;

import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.Item;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.neoforged.neoforge.registries.DeferredBlock;
import net.neoforged.neoforge.registries.DeferredRegister;

import java.util.function.Function;

/**
 * Block + block-item registry. Add new blocks via the {@link #register} helper:
 * pairs a {@code DeferredBlock} with an automatic {@code BlockItem} of the same name.
 */
public final class ModBlocks {
    public static final DeferredRegister.Blocks BLOCKS = DeferredRegister.createBlocks(MyFirstMod.MODID);
    public static final DeferredRegister.Items ITEMS = DeferredRegister.createItems(MyFirstMod.MODID);

    private static <T extends Block> DeferredBlock<T> register(
            String name,
            Function<BlockBehaviour.Properties, T> ctor,
            BlockBehaviour.Properties props
    ) {
        DeferredBlock<T> block = BLOCKS.register(name, () -> ctor.apply(props));
        ITEMS.register(name, () -> new BlockItem(block.get(), new Item.Properties()));
        return block;
    }

    private ModBlocks() {}
}
