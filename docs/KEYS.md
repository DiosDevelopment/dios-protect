# Vehicle-key integrations

The resource requires no utility library. Optional key providers must start before dios_protect. `Protect.integration.keys='auto'` uses every started provider; an explicit ID selects one. `Protect.keyResources` supports renamed resources. Missing exports or failed ownership verification abort deployment with a server diagnostic. Installations must still test their exact provider version in both GTA editions.

| Adapter ID | Resource | Grant and verification | Primary API reference |
| --- | --- | --- | --- |
| qbox | qbx_vehiclekeys | Server GiveKeys / HasKeys, entity | [QBox](https://docs.qbox.re/resources/qbx_vehiclekeys/exports/server) |
| qbcore | qb-vehiclekeys | Server GiveKeys / HasKeys, plate; requires modern exports | [QBCore source](https://github.com/qbcore-framework/qb-vehiclekeys/blob/main/server.lua) |
| wasabi | wasabi_carlock | Server GiveKey / HasKey, plate | [Wasabi](https://docs.wasabiscripts.com/advanced-series/wasabi-carlock/exports) |
| renewed | Renewed-Vehiclekeys | Server addKey / hasKey, plate; vehicleLock state | [Renewed](https://github.com/Renewed-Scripts/Renewed-Docs/blob/main/paid-scripts/renewed-vehiclekeys/exports.md) |
| mrnewb | MrNewbVehicleKeys | Server GiveKeys / HaveKeys, network ID | [MrNewb](https://mrnewbs-scrips.gitbook.io/guide/vehiclekeys/vehicle-keys-exports/server-exports) |
| zrx | zrx_carlock | Server giveKey / hasKey, plate | [ZRX](https://docs.zrxnx.at/zrxnx-scripts/scripts/zrx_carlock/exports) |
| jaksam | vehicles_keys | Server giveVehicleKeysToPlayerId, temporary; dispatch confirmation | [Jaksam](https://documentation.jaksam-scripts.com/vehicles-keys/server/give-keys-to-player-id) |
| quasar | qs-vehiclekeys | Client GiveKeys / GetKey, plate and model display name | [Quasar](https://www.quasar-store.com/docs/vehiclekeys/commands-and-exports) |
| codesign | cd_garage | Client AddKeys event / DoesPlayerHaveKeys | [Codesign](https://docs.codesign.pro/paid-scripts/garage/developer-api/exports) |
| okok | okokGarage | Client GiveKeys server event; dispatch confirmation | [okok](https://docs.okokscripts.io/scripts/okokgarage) |
| t1ger | t1ger_keys | Client GiveTemporaryKeys and SetVehicleLocked; dispatch confirmation | [T1ger](https://docs.t1ger.net/free-resources/t1ger-keys) |
| mk | mk_vehiclekeys | Client AddKey(vehicle entity); dispatch confirmation, version dependent | [JG integration](https://docs.jgscripts.com/advanced-garages/integrations/custom-key-system) |
| ak47 | ak47_vehiclekeys | Client GiveKey(plate,false); dispatch confirmation, version dependent | [CodeM integration source](https://github.com/Aiakos232/codem-lib/blob/main/modules/vehiclekeys/client.lua) |
| ak47qb | ak47_qb_vehiclekeys | Server GiveKey / HasKey, plate | [AK47](https://docs.menanak47.com/qbcore/ak47_qb_vehiclekeys/integration) |

Keys are granted to the President after staging ground vehicles and after creating air support. There is no public key-grant endpoint. Client grants are authenticated server requests matching network ID, model and plate. Every successful provider must be able to keep those vehicles enterable; native unlocking alone cannot override an unrelated lock resource. Dispatch-only adapters cannot prove that an event was handled or a player received usable keys. Confirm entry, locking, unlocking and re-entry in game, including simultaneous providers. An unsupported export fails visibly; use the custom adapter for a different API version.

For custom providers implement `ProtectIntegration.giveKeys(source,vehicle)` in config/integration.lua and return `true` after confirming delivery. Key item removal/persistence remains with the provider; deleting convoy entities does not remove key inventory items. This resource does not change provider databases or permanently register convoy vehicles as player-owned vehicles.
