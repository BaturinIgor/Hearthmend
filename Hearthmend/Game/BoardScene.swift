import SpriteKit
import HearthCore

/// Поле слияния. Рисует состояние из GameStore и превращает касания в действия:
/// тап - генератор, пузырь или выбор предмета, перетаскивание - перемещение и слияние.
/// Графика временная (эмодзи), спрайты пака подключим отдельным шагом.
@MainActor
final class BoardScene: SKScene {
    weak var store: GameStore?

    private let boardNode = SKNode()
    private var contentNodes: [Int: SKNode] = [:]
    private var cellSize: CGFloat = 40
    private var origin: CGPoint = .zero

    private var touchStart: CGPoint?
    private var touchIndex: Int?
    private var dragging: SKNode?
    /// Когда игрок последний раз трогал поле: после паузы подмигивает пара для слияния.
    private var lastTouch: TimeInterval = 0
    private var lastHint: TimeInterval = 0
    private static let idleHintDelay: TimeInterval = 7

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = Palette.board
        anchorPoint = .zero
        addChild(boardNode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        render()
    }

    // MARK: - Раскладка

    private var cols: Int { store?.balance.cols ?? 7 }
    private var rows: Int { store?.balance.rows ?? 9 }

    private func layout() {
        let pad: CGFloat = 6
        cellSize = floor(min((size.width - pad * 2) / CGFloat(cols), (size.height - pad * 2) / CGFloat(rows)))
        let w = cellSize * CGFloat(cols), h = cellSize * CGFloat(rows)
        origin = CGPoint(x: (size.width - w) / 2, y: (size.height - h) / 2)
    }

    /// Центр клетки. Ряд 0 - верхний.
    private func center(of index: Int) -> CGPoint {
        let r = index / cols, c = index % cols
        return CGPoint(x: origin.x + (CGFloat(c) + 0.5) * cellSize,
                       y: origin.y + (CGFloat(rows - 1 - r) + 0.5) * cellSize)
    }

    private func index(at point: CGPoint) -> Int? {
        let c = Int(floor((point.x - origin.x) / cellSize))
        let rFromBottom = Int(floor((point.y - origin.y) / cellSize))
        guard c >= 0, c < cols, rFromBottom >= 0, rFromBottom < rows else { return nil }
        return (rows - 1 - rFromBottom) * cols + c
    }

    // MARK: - Отрисовка

    func render() {
        guard let store, size.width > 0, size.height > 0 else { return }
        layout()
        boardNode.removeAllChildren()
        contentNodes.removeAll()
        let state = store.game.state
        let needed = store.game.neededItems
        for i in state.cells.indices {
            let tile = SKShapeNode(rectOf: CGSize(width: cellSize - 3, height: cellSize - 3), cornerRadius: cellSize * 0.18)
            tile.position = center(of: i)
            let r = i / cols, c = i % cols
            tile.fillColor = (r + c) % 2 == 0 ? Palette.tileA : Palette.tileB
            tile.strokeColor = .clear
            tile.zPosition = 0
            boardNode.addChild(tile)

            if let piece = state.cells[i] {
                let node = makeNode(for: piece, highlighted: piece.item.map { needed.contains($0) } ?? false)
                node.position = center(of: i)
                node.zPosition = 1
                boardNode.addChild(node)
                contentNodes[i] = node
            }
        }
        updateSelection()
        tutorialHints(state)
    }

    /// Подсказки обучения: пульсирующие рамки на генераторе или на паре одинаковых предметов.
    private func tutorialHints(_ state: GameState) {
        guard let store else { return }
        var cells: [Int] = []
        switch store.game.tutorial {
        case .spawn:
            if let g = state.cells.firstIndex(where: { if case .generator? = $0 { return true } else { return false } }) {
                cells = [g]
            }
        case .merge:
            var seen: [Item: Int] = [:]
            for (i, piece) in state.cells.enumerated() {
                guard let item = piece?.item, store.catalog.next(item) != nil else { continue }
                if let j = seen[item] { cells = [j, i]; break }
                seen[item] = i
            }
        default:
            break
        }
        for i in cells {
            let ring = SKShapeNode(rectOf: CGSize(width: cellSize - 1, height: cellSize - 1), cornerRadius: cellSize * 0.2)
            ring.strokeColor = .white
            ring.lineWidth = 3
            ring.glowWidth = 4
            ring.position = center(of: i)
            ring.zPosition = 3
            ring.run(.repeatForever(.sequence([
                .group([.scale(to: 1.12, duration: 0.5), .fadeAlpha(to: 0.4, duration: 0.5)]),
                .group([.scale(to: 1.0, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)]),
            ])))
            boardNode.addChild(ring)
        }
    }

    /// Только рамка выбора, без перерисовки поля: анимации слияния и полета не обрываются.
    func updateSelection() {
        boardNode.childNode(withName: "selection")?.removeFromParent()
        guard let i = store?.selected else { return }
        let ring = SKShapeNode(rectOf: CGSize(width: cellSize - 3, height: cellSize - 3), cornerRadius: cellSize * 0.18)
        ring.name = "selection"
        ring.strokeColor = Palette.selected
        ring.lineWidth = 3
        ring.position = center(of: i)
        ring.zPosition = 2
        ring.setScale(0.85)
        ring.run(.scale(to: 1, duration: 0.12))
        boardNode.addChild(ring)
    }

    private func makeNode(for piece: Piece, highlighted: Bool) -> SKNode {
        guard let catalog = store?.catalog else { return SKNode() }
        let node = SKNode()
        switch piece {
        case .item(let item):
            if highlighted {
                let glow = SKShapeNode(circleOfRadius: cellSize * 0.42)
                glow.fillColor = Palette.needed
                glow.strokeColor = .clear
                node.addChild(glow)
            }
            node.addChild(icon(key: catalog.key(for: item), fallback: catalog.emoji(for: item), scale: 0.62))
            node.addChild(badge("\(item.tier + 1)"))
        case .generator(let gen):
            let base = SKShapeNode(rectOf: CGSize(width: cellSize * 0.86, height: cellSize * 0.86), cornerRadius: cellSize * 0.2)
            base.fillColor = Palette.generator
            base.strokeColor = Palette.generatorStroke
            base.lineWidth = 2
            node.addChild(base)
            let def = catalog.chain(gen.chain)
            node.addChild(icon(key: def?.generator ?? "", fallback: def?.generatorEmoji ?? "?", scale: 0.6))
            node.addChild(badge(String(repeating: "★", count: gen.tier + 1)))
        case .debris(let layers):
            let base = SKShapeNode(rectOf: CGSize(width: cellSize - 3, height: cellSize - 3), cornerRadius: cellSize * 0.18)
            base.fillColor = Palette.debris
            base.strokeColor = .clear
            node.addChild(base)
            node.addChild(icon(key: "debris", fallback: "🧱", scale: 0.5))
            if layers > 1 { node.addChild(badge("\(layers)")) }
        case .bubble(let item, _):
            let bubble = SKShapeNode(circleOfRadius: cellSize * 0.44)
            bubble.fillColor = Palette.bubble
            bubble.strokeColor = .white
            bubble.lineWidth = 2
            node.addChild(bubble)
            let inner = icon(key: catalog.key(for: item), fallback: catalog.emoji(for: item), scale: 0.5)
            inner.alpha = 0.8
            node.addChild(inner)
            node.addChild(badge("💎\(store?.balance.popCost(item) ?? 0)"))
            node.run(.repeatForever(.sequence([.scale(to: 1.05, duration: 0.6), .scale(to: 0.95, duration: 0.6)])))
        }
        return node
    }

    /// Спрайт из пака, если он есть в сборке, иначе эмодзи. scale - доля клетки.
    private func icon(key: String, fallback: String, scale: CGFloat) -> SKNode {
        guard let texture = Sprites.texture(key) else { return emoji(fallback, scale: scale) }
        let sprite = SKSpriteNode(texture: texture)
        let side = cellSize * (scale + 0.12)
        let k = side / max(texture.size().width, texture.size().height)
        sprite.size = CGSize(width: texture.size().width * k, height: texture.size().height * k)
        return sprite
    }

    private func emoji(_ text: String, scale: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(text: text)
        label.fontSize = cellSize * scale
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }

    private func badge(_ text: String) -> SKLabelNode {
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Bold"
        label.fontSize = cellSize * 0.2
        label.fontColor = Palette.badge
        label.horizontalAlignmentMode = .right
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: cellSize * 0.42, y: -cellSize * 0.44)
        return label
    }

    // MARK: - Подсказки

    override func update(_ currentTime: TimeInterval) {
        if lastTouch == 0 { lastTouch = currentTime }
        guard let store, store.game.tutorial == .done, dragging == nil,
              currentTime - lastTouch > Self.idleHintDelay,
              currentTime - lastHint > Self.idleHintDelay,
              let pair = store.game.mergeHint() else { return }
        lastHint = currentTime
        for i in [pair.0, pair.1] { wiggle(at: i) }
    }

    /// Предметы, нужные заказу: подпрыгивают с рамкой. Если их нет на поле - легкая тряска заказа не нужна,
    /// просто ничего не подсвечиваем.
    func highlight(_ cells: [Int]) {
        for i in cells {
            guard let node = contentNodes[i] else { continue }
            node.removeAction(forKey: "hint")
            node.run(.sequence([.scale(to: 1.25, duration: 0.12), .scale(to: 0.95, duration: 0.1), .scale(to: 1, duration: 0.08)]), withKey: "hint")
            let ring = SKShapeNode(rectOf: CGSize(width: cellSize - 1, height: cellSize - 1), cornerRadius: cellSize * 0.2)
            ring.strokeColor = Palette.selected
            ring.lineWidth = 3
            ring.glowWidth = 3
            ring.position = center(of: i)
            ring.zPosition = 3
            boardNode.addChild(ring)
            ring.run(.sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
        }
    }

    private func wiggle(at index: Int) {
        guard let node = contentNodes[index] else { return }
        let r: CGFloat = 0.12
        node.run(.sequence([
            .rotate(toAngle: r, duration: 0.07), .rotate(toAngle: -r, duration: 0.12),
            .rotate(toAngle: r, duration: 0.12), .rotate(toAngle: 0, duration: 0.07),
        ]), withKey: "hint")
    }

    // MARK: - Касания

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouch = CACurrentMediaTime()
        guard let touch = touches.first else { return }
        let p = touch.location(in: self)
        touchStart = p
        touchIndex = index(at: p)
        dragging = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let start = touchStart, let from = touchIndex else { return }
        let p = touch.location(in: self)
        if dragging == nil {
            guard hypot(p.x - start.x, p.y - start.y) > 8,
                  let piece = store?.game.piece(at: from), piece.isMovable,
                  let node = contentNodes[from] else { return }
            node.zPosition = 10
            node.run(.scale(to: 1.15, duration: 0.08))
            dragging = node
        }
        dragging?.position = p
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            touchStart = nil
            touchIndex = nil
            dragging = nil
        }
        guard let store, let touch = touches.first, let from = touchIndex else { return }
        let p = touch.location(in: self)
        guard let dragged = dragging else {
            let result = store.tap(from)
            render()
            if case .spawned(let cell, _)? = result {
                squish(at: from)
                fly(cell, from: center(of: from))
            } else if case .noEnergy? = result {
                shake(at: from)
            }
            return
        }
        guard let to = index(at: p), to != from else {
            // мимо поля или на то же место: предмет плавно возвращается
            dragged.run(.group([.move(to: center(of: from), duration: 0.16), .scale(to: 1, duration: 0.16)])) { [weak self] in
                self?.render()
            }
            return
        }
        let result = store.move(from: from, to: to)
        render()
        switch result {
        case .merged(_, let cleared, let bubble):
            pop(at: to)
            sparkle(at: to)
            for i in cleared { dust(at: i) }
            if let bubble { fly(bubble, from: center(of: to)) }
        case .mergedGenerator:
            pop(at: to)
            sparkle(at: to)
        case .moved:
            slide(to, from: p)
        case .swapped:
            slide(to, from: p)
            slide(from, from: center(of: to))
        case .invalid:
            slide(from, from: p)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
        touchIndex = nil
        dragging = nil
        render()
    }

    // MARK: - Эффекты

    private func pop(at index: Int) {
        guard let node = contentNodes[index] else { return }
        node.setScale(0.6)
        node.run(.sequence([.scale(to: 1.2, duration: 0.1), .scale(to: 1.0, duration: 0.08)]))
    }

    /// Предмет приезжает в свою клетку из точки, где его отпустили.
    private func slide(_ index: Int, from point: CGPoint) {
        guard let node = contentNodes[index] else { return }
        let target = node.position
        node.position = point
        let move = SKAction.move(to: target, duration: 0.14)
        move.timingMode = .easeOut
        node.run(move)
    }

    /// Новый предмет вылетает из генератора по дуге.
    private func fly(_ index: Int, from start: CGPoint) {
        guard let node = contentNodes[index] else { return }
        let end = node.position
        let lift = max(cellSize * 0.8, hypot(end.x - start.x, end.y - start.y) * 0.35)
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + lift))
        node.position = start
        node.setScale(0.3)
        let follow = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 0.28)
        follow.timingMode = .easeOut
        node.run(.sequence([
            .group([follow, .scale(to: 1.0, duration: 0.28)]),
            .scale(to: 1.12, duration: 0.06),
            .scale(to: 1.0, duration: 0.08),
        ]))
    }

    /// Генератор приседает, когда выдает предмет.
    private func squish(at index: Int) {
        guard let node = contentNodes[index] else { return }
        node.run(.sequence([
            .group([.scaleX(to: 1.12, duration: 0.06), .scaleY(to: 0.88, duration: 0.06)]),
            .group([.scaleX(to: 0.96, duration: 0.08), .scaleY(to: 1.06, duration: 0.08)]),
            .scale(to: 1.0, duration: 0.06),
        ]))
    }

    private func shake(at index: Int) {
        guard let node = contentNodes[index] else { return }
        let d = cellSize * 0.06
        node.run(.sequence([.moveBy(x: d, y: 0, duration: 0.04), .moveBy(x: -2 * d, y: 0, duration: 0.06),
                            .moveBy(x: 2 * d, y: 0, duration: 0.06), .moveBy(x: -d, y: 0, duration: 0.04)]))
    }

    /// Искры при слиянии.
    private func sparkle(at index: Int) {
        let c = center(of: index)
        for k in 0..<8 {
            let angle = CGFloat(k) / 8 * .pi * 2
            let star = SKShapeNode(circleOfRadius: cellSize * 0.05)
            star.fillColor = k.isMultiple(of: 2) ? .white : Palette.needed
            star.strokeColor = .clear
            star.position = c
            star.zPosition = 6
            boardNode.addChild(star)
            let out = SKAction.moveBy(x: cos(angle) * cellSize * 0.6, y: sin(angle) * cellSize * 0.6, duration: 0.3)
            out.timingMode = .easeOut
            star.run(.sequence([.group([out, .fadeOut(withDuration: 0.3), .scale(to: 0.3, duration: 0.3)]), .removeFromParent()]))
        }
    }

    private func dust(at index: Int) {
        let puff = SKShapeNode(circleOfRadius: cellSize * 0.35)
        puff.fillColor = Palette.debris
        puff.strokeColor = .clear
        puff.position = center(of: index)
        puff.zPosition = 5
        boardNode.addChild(puff)
        puff.run(.sequence([.group([.scale(to: 1.6, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
    }
}

/// Спрайты пака лежат в бандле как <ключ>.png (их распаковывает CI из Art/sprites.enc).
/// Пиксель-арт масштабируется без сглаживания.
@MainActor
enum Sprites {
    private static var cache: [String: SKTexture?] = [:]

    static func texture(_ key: String) -> SKTexture? {
        if let cached = cache[key] { return cached }
        var texture: SKTexture?
        if let image = image(key) {
            let t = SKTexture(image: image)
            t.filteringMode = .nearest
            texture = t
        }
        cache[key] = texture
        return texture
    }

    static func image(_ key: String) -> UIImage? {
        guard !key.isEmpty, let path = Bundle.main.path(forResource: key, ofType: "png") else { return nil }
        return UIImage(contentsOfFile: path)
    }
}

enum Palette {
    static let board = UIColor(red: 0.42, green: 0.58, blue: 0.33, alpha: 1)
    static let tileA = UIColor(red: 0.62, green: 0.78, blue: 0.47, alpha: 1)
    static let tileB = UIColor(red: 0.57, green: 0.73, blue: 0.43, alpha: 1)
    static let generator = UIColor(red: 0.96, green: 0.86, blue: 0.62, alpha: 1)
    static let generatorStroke = UIColor(red: 0.62, green: 0.42, blue: 0.22, alpha: 1)
    static let debris = UIColor(red: 0.48, green: 0.40, blue: 0.33, alpha: 1)
    static let bubble = UIColor(red: 0.62, green: 0.86, blue: 0.98, alpha: 0.6)
    static let selected = UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)
    static let needed = UIColor(red: 0.85, green: 1.0, blue: 0.6, alpha: 0.75)
    static let badge = UIColor(red: 0.30, green: 0.20, blue: 0.10, alpha: 1)
}
