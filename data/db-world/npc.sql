@ENTRY = 133337;
@Name = "Jack";
@Subname = "Of All Classes";
DELETE FROM `creature_template` WHERE (`entry` = @ENTRY);
INSERT INTO `creature_template` (`entry`, `name`, `subname`, `difficulty_entry_1`, `difficulty_entry_2`, `difficulty_entry_3`, `KillCredit1`, `KillCredit2`, `name`, `subname`, `IconName`, `gossip_menu_id`, `minlevel`, `maxlevel`, `exp`, `faction`, `npcflag`, `speed_walk`, `speed_run`, `speed_swim`, `speed_flight`, `detection_range`, `scale`, `rank`, `dmgschool`, `DamageModifier`, `BaseAttackTime`, `RangeAttackTime`, `BaseVariance`, `RangeVariance`, `unit_class`, `unit_flags`, `unit_flags2`, `dynamicflags`, `family`, `type`, `type_flags`, `lootid`, `pickpocketloot`, `skinloot`, `PetSpellDataId`, `VehicleId`, `mingold`, `maxgold`, `AIName`, `MovementType`, `HoverHeight`, `HealthModifier`, `ManaModifier`, `ArmorModifier`, `ExperienceModifier`, `RacialLeader`, `movementId`, `RegenHealth`, `mechanic_immune_mask`, `spell_school_immune_mask`, `flags_extra`, `ScriptName`, `VerifiedBuild`) VALUES
(@ENTRY, @Name, @Subname, 0, 0, 0, 0, '', '', '', 0, 80, 80, 0, 2142, 17, 1, 1.14286, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0, 0, 8, 2, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, '', 0, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0, 0, 'npc_multiclasser', 0);

DELETE FROM `creature_template_model` WHERE `CreatureID` = @Entry;
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`) VALUES
(@Entry, 0, @ENTRY, 1, 1, 0);

DELETE FROM `creature_template_locale` WHERE `entry` IN  (@Entry);
INSERT INTO `creature_template_locale` (`entry`, `locale`, `Name`, `Title`) VALUES
(@Entry, 'ruRU', "Джек", "Мастер на все руки");