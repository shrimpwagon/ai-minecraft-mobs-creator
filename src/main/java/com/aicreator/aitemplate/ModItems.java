package com.aicreator.aitemplate;

import net.neoforged.neoforge.registries.DeferredRegister;

/** Standalone item registry (non-block items: food, materials, tools, spawn eggs). Empty scaffold. */
public final class ModItems {
    public static final DeferredRegister.Items ITEMS = DeferredRegister.createItems(MyFirstMod.MODID);

    private ModItems() {}
}
