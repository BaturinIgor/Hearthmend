import Foundation

/// Обучение: Мила ведет новичка по первым шагам. Шаг меняется сам, когда игрок делает нужное действие.
public enum TutorialStep: Int, CaseIterable {
    /// Тапни по генератору.
    case spawn
    /// Слей два одинаковых предмета.
    case merge
    /// Отдай заказ.
    case deliver
    /// Построй первое здание в деревне.
    case build
    case done
}

extension Game {
    public var tutorial: TutorialStep { TutorialStep(rawValue: state.tutorialStep) ?? .done }

    /// Переходит к следующему шагу, если сейчас ждали именно это действие.
    func advanceTutorial(from step: TutorialStep) {
        guard tutorial == step, step != .done else { return }
        state.tutorialStep = step.rawValue + 1
    }

    public func skipTutorial() {
        state.tutorialStep = TutorialStep.done.rawValue
    }
}
