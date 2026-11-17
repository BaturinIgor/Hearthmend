import Foundation

/// Животные деревни. Когда открывается район, в него можно взять животное за монеты.
/// Животное гуляет по своему району на карте, и раз в день у него можно забрать маленький подарок:
/// повод заглянуть в деревню. Монеты в игре копятся, а здесь у них появляется приятная трата.
public struct PetDef: Equatable {
    public let id: String
    /// Район, который должен быть открыт.
    public let district: String
    public let cost: Int
    /// Ежедневный подарок.
    public let gift: ProductReward
}

public enum Pets {
    public static let all: [PetDef] = [
        PetDef(id: "chicken", district: "farmstead", cost: 600, gift: ProductReward(energy: 4)),
        PetDef(id: "sheep", district: "farmstead", cost: 1_200, gift: ProductReward(coins: 60)),
        PetDef(id: "duck", district: "riverside", cost: 1_500, gift: ProductReward(energy: 5)),
        PetDef(id: "frog", district: "riverside", cost: 2_000, gift: ProductReward(gems: 1)),
        PetDef(id: "pig", district: "orchard", cost: 2_800, gift: ProductReward(coins: 100)),
        PetDef(id: "goose", district: "orchard", cost: 3_500, gift: ProductReward(energy: 6)),
        PetDef(id: "cow", district: "hilltop", cost: 4_500, gift: ProductReward(energy: 7)),
        PetDef(id: "swan", district: "hilltop", cost: 5_500, gift: ProductReward(gems: 2)),
        PetDef(id: "horse", district: "mine", cost: 7_000, gift: ProductReward(energy: 8)),
        PetDef(id: "mouse", district: "fair", cost: 9_000, gift: ProductReward(gems: 3)),
    ]

    public static func def(_ id: String) -> PetDef? { all.first { $0.id == id } }
}

extension Game {
    public func petOwned(_ id: String) -> Bool { state.petsOwned.contains(id) }

    /// Район животного открыт: его можно взять.
    public func petAvailable(_ id: String) -> Bool {
        guard let pet = Pets.def(id), let district = village.districts.first(where: { $0.id == pet.district }) else { return false }
        return isDistrictOpen(district)
    }

    public func canAdopt(_ id: String) -> Bool {
        guard let pet = Pets.def(id) else { return false }
        return !petOwned(id) && petAvailable(id) && state.coins >= pet.cost
    }

    /// Взять животное за монеты.
    @discardableResult
    public func adoptPet(_ id: String) -> Bool {
        guard canAdopt(id), let pet = Pets.def(id) else { return false }
        state.coins -= pet.cost
        state.petsOwned.append(id)
        // в первый день подарок уже ждет
        state.petGiftDay[id] = questDay - 1
        return true
    }

    public func petGiftReady(_ id: String) -> Bool {
        petOwned(id) && (state.petGiftDay[id] ?? Int.min) < questDay
    }

    public var petGiftsReady: Int { state.petsOwned.filter(petGiftReady).count }

    /// Забрать подарок животного (раз в сутки, по UTC, как задания дня).
    public func collectPet(_ id: String) -> ProductReward? {
        guard petGiftReady(id), let pet = Pets.def(id) else { return nil }
        state.petGiftDay[id] = questDay
        grant(pet.gift)
        return pet.gift
    }
}
