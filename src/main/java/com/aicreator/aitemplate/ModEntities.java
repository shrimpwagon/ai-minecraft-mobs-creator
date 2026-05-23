package com.aicreator.aitemplate;

import net.minecraft.core.registries.Registries;
import net.minecraft.world.entity.EntityType;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Entity-type registry. Empty scaffold — add EntityType.Builder entries here per new mob. */
public final class ModEntities {
    public static final DeferredRegister<EntityType<?>> ENTITY_TYPES =
            DeferredRegister.create(Registries.ENTITY_TYPE, MyFirstMod.MODID);

    private ModEntities() {}
}
