package com.aicreator.aitemplate;

import com.mojang.logging.LogUtils;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.common.Mod;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;
import net.neoforged.neoforge.event.entity.EntityAttributeCreationEvent;
import net.neoforged.neoforge.event.entity.RegisterSpawnPlacementsEvent;
import org.slf4j.Logger;

/**
 * Mod entry point. Empty scaffold:
 *  - {@link #onAttributeCreation} — add {@code event.put(ModEntities.X.get(), XEntity.createAttributes().build());} per mob.
 *  - {@link #onSpawnPlacementRegister} — add {@code event.register(ModEntities.X.get(), ...)} per mob that spawns naturally (skip for spawn-egg-only mobs).
 *  - {@link ClientEvents#onRegisterRenderers} — add {@code event.registerEntityRenderer(ModEntities.X.get(), XRenderer::new);} per mob.
 */
@Mod(MyFirstMod.MODID)
public class MyFirstMod {
    public static final String MODID = "aitemplate";
    public static final Logger LOGGER = LogUtils.getLogger();

    public MyFirstMod(IEventBus modEventBus) {
        ModBlocks.BLOCKS.register(modEventBus);
        ModBlocks.ITEMS.register(modEventBus);
        ModItems.ITEMS.register(modEventBus);
        ModEntities.ENTITY_TYPES.register(modEventBus);
        ModCreativeTab.CREATIVE_MODE_TABS.register(modEventBus);

        modEventBus.addListener(MyFirstMod::onAttributeCreation);
        modEventBus.addListener(MyFirstMod::onSpawnPlacementRegister);

        LOGGER.info("{} loaded — clean scaffold, no assets registered yet.", MODID);
    }

    private static void onAttributeCreation(EntityAttributeCreationEvent event) {
        // event.put(ModEntities.X.get(), XEntity.createAttributes().build());
    }

    private static void onSpawnPlacementRegister(RegisterSpawnPlacementsEvent event) {
        // event.register(ModEntities.X.get(),
        //         net.minecraft.world.entity.SpawnPlacementTypes.ON_GROUND,
        //         net.minecraft.world.level.levelgen.Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
        //         net.minecraft.world.entity.monster.Monster::checkAnyLightMonsterSpawnRules,
        //         RegisterSpawnPlacementsEvent.Operation.REPLACE);
    }

    @EventBusSubscriber(modid = MODID, bus = EventBusSubscriber.Bus.MOD, value = Dist.CLIENT)
    public static final class ClientEvents {
        @SubscribeEvent
        public static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
            // event.registerEntityRenderer(ModEntities.X.get(), XRenderer::new);
        }
    }
}
