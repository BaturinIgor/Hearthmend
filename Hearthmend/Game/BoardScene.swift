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
        backgroundColor = .clear
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

    /// Что нарисовано в клетке: узел пересоздается, только когда это меняется.
    /// Так быстрые тапы по генератору не обрывают полет уже вылетевших предметов.
    private var drawn: [Int: String] = [:]
    private var tiles: [SKNode] = []
    private var layoutKey = ""

    func render() {
        guard let store, size.width > 0, size.height > 0 else { return }
        layout()
        let key = "\(cellSize)|\(origin)|\(cols)x\(rows)"
        if key != layoutKey {
            layoutKey = key
            boardNode.removeAllChildren()
            contentNodes.removeAll()
            drawn.removeAll()
            tiles = []
            for i in 0..<(cols * rows) {
                let r = i / cols, c = i % cols
                let tile: SKNode
                if let texture = Sprites.texture((r + c) % 2 == 0 ? "ui_cell_a" : "ui_cell_b") {
                    // пиксельные клетки травы из tools/ui_kit.py
                    tile = SKSpriteNode(texture: texture, size: CGSize(width: cellSize, height: cellSize))
                } else {
                    let shape = SKShapeNode(rectOf: CGSize(width: cellSize - 3, height: cellSize - 3), cornerRadius: cellSize * 0.18)
                    shape.fillColor = (r + c) % 2 == 0 ? Palette.tileA : Palette.tileB
                    shape.strokeColor = .clear
                    tile = shape
                }
                tile.position = center(of: i)
                tile.zPosition = 0
                boardNode.addChild(tile)
                tiles.append(tile)
            }
        }
        let state = store.game.state
        let needed = store.game.neededItems
        for i in state.cells.indices {
            let piece = state.cells[i]
            let highlighted = piece?.item.map { needed.contains($0) } ?? false
            let revealed = store.game.isRevealed(i)
            let rowChest = i % cols == cols - 1 && state.thicketRows.contains(i / cols)
            let sig = piece.map { "\($0)|\(highlighted)|\(revealed)|\(rowChest)" } ?? ""
            if drawn[i] == sig, contentNodes[i] != nil || piece == nil { continue }
            contentNodes[i]?.removeFromParent()
            contentNodes[i] = nil
            drawn[i] = sig
            guard let piece else { continue }
            let node = makeNode(for: piece, highlighted: highlighted, revealed: revealed, rowChest: rowChest, index: i)
            node.position = center(of: i)
            node.zPosition = 1
            boardNode.addChild(node)
            contentNodes[i] = node
        }
        boardNode.children.filter { $0.name == "tutorial" }.forEach { $0.removeFromParent() }
        updateSelection()
        tutorialHints(state)
    }

    /// Узел клетки больше не соответствует состоянию (его тащили): нарисовать заново.
    private func forget(_ index: Int) {
        contentNodes[index]?.removeFromParent()
        contentNodes[index] = nil
        drawn[index] = nil
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
            ring.name = "tutorial"
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

    private func makeNode(for piece: Piece, highlighted: Bool, revealed: Bool = true, rowChest: Bool = false, index: Int = 0) -> SKNode {
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
            node.addChild(shadow(width: 0.5))
            node.addChild(icon(key: catalog.key(for: item), fallback: catalog.emoji(for: item), scale: 0.7))
            node.addChild(badge("\(item.tier + 1)"))
        case .generator(let gen):
            // источник стоит на теплом пятне света, а не в ящике
            let glow = SKShapeNode(circleOfRadius: cellSize * 0.44)
            glow.fillColor = UIColor(red: 1, green: 0.93, blue: 0.62, alpha: 0.55)
            glow.strokeColor = UIColor(red: 1, green: 0.98, blue: 0.85, alpha: 0.8)
            glow.lineWidth = 1.5
            node.addChild(glow)
            node.addChild(shadow(width: 0.6))
            let def = catalog.chain(gen.chain)
            node.addChild(icon(key: def?.generator ?? "", fallback: def?.generatorEmoji ?? "?", scale: 0.68))
            node.addChild(stars(gen.tier + 1))
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
            node.addChild(badge("\(store?.balance.popCost(item) ?? 0)", icon: "ui_gem"))
            node.run(.repeatForever(.sequence([.scale(to: 1.05, duration: 0.6), .scale(to: 0.95, duration: 0.6)])))
        case .thicket(let item):
            let base = SKShapeNode(rectOf: CGSize(width: cellSize - 2, height: cellSize - 2), cornerRadius: cellSize * 0.16)
            base.fillColor = revealed ? Palette.thicketOpen : Palette.thicket
            base.strokeColor = .clear
            node.addChild(base)
            let leaves = icon(key: "thicket_\(index % 3)", fallback: "🌿", scale: 0.78)
            node.addChild(leaves)
            if revealed {
                // предмет просвечивает сквозь листву: видно, что положить сверху
                let inner = icon(key: catalog.key(for: item), fallback: catalog.emoji(for: item), scale: 0.42)
                inner.alpha = 0.9
                inner.zPosition = 1
                node.addChild(inner)
                node.addChild(badge("\(item.tier + 1)"))
                leaves.alpha = 0.75
            } else {
                leaves.alpha = 0.95
            }
            if rowChest {
                // ящик за расчищенный ряд висит на краю ряда
                let mark = icon(key: "chest_0", fallback: "🎁", scale: 0.22)
                mark.position = CGPoint(x: cellSize * 0.3, y: cellSize * 0.3)
                mark.zPosition = 2
                node.addChild(mark)
            }
        case .chest(let chest):
            let glow = SKShapeNode(circleOfRadius: cellSize * 0.4)
            glow.fillColor = Palette.chestGlow
            glow.strokeColor = .clear
            node.addChild(glow)
            if chest.kind == .items {
                node.addChild(icon(key: Self.chestKey(chest), fallback: "🎁", scale: 0.6))
                if let left = chest.left { node.addChild(badge("\(left)", icon: "ui_basket")) }
                else { node.addChild(stars(chest.level + 1)) }
            } else {
                // кучка ресурса растет с уровнем: 1-3 значка, дальше мешочек, банка, сундучок
                let (key, count) = Self.resourceArt(chest)
                let offsets: [[CGPoint]] = [[.zero],
                                            [CGPoint(x: -0.12, y: -0.06), CGPoint(x: 0.12, y: 0.06)],
                                            [CGPoint(x: -0.14, y: -0.1), CGPoint(x: 0.14, y: -0.1), CGPoint(x: 0, y: 0.12)]]
                for p in offsets[max(0, min(count, 3) - 1)] {
                    let sprite = icon(key: key, fallback: "✨", scale: count > 1 ? 0.4 : 0.55)
                    sprite.position = CGPoint(x: p.x * cellSize, y: p.y * cellSize)
                    node.addChild(sprite)
                }
                node.addChild(badge("\(chest.level + 1)"))
            }
            node.run(.repeatForever(.sequence([.wait(forDuration: 2.5 + Double(index % 5) * 0.4),
                                              .rotate(byAngle: 0.08, duration: 0.07), .rotate(byAngle: -0.16, duration: 0.1),
                                              .rotate(byAngle: 0.08, duration: 0.07)])))
        }
        return node
    }

    nonisolated static func chestKey(_ chest: Chest, open: Bool = false) -> String {
        let base = chest.level >= 3 ? "chest_3_\(chest.kind.rawValue)" : "chest_\(max(0, chest.level))"
        return open ? base + "_open" : base
    }

    /// Картинка ресурса на поле и сколько раз ее повторить.
    nonisolated static func resourceArt(_ chest: Chest) -> (String, Int) {
        let l = chest.level
        switch chest.kind {
        case .coins: return l < 3 ? ("ui_coin", l + 1) : l < 6 ? ("ui_pouch", 1) : ("ui_vault", 1)
        case .energy: return l < 3 ? ("ui_energy", l + 1) : ("ui_jar", 1)
        case .gems: return l < 3 ? ("ui_gem", l + 1) : l < 5 ? ("ui_bag", 1) : ("ui_chest", 1)
        case .items: return (chestKey(chest), 1)
        }
    }

    nonisolated static func chestIcon(_ kind: ChestKind) -> String {
        switch kind {
        case .items: return "ui_basket"
        case .coins: return "ui_coin"
        case .energy: return "ui_energy"
        case .gems: return "ui_gem"
        }
    }

    /// Спрайт из пака, если он есть в сборке, иначе эмодзи. scale - доля клетки.
    private func icon(key: String, fallback: String, scale: CGFloat) -> SKNode {
        guard let texture = Sprites.texture(key) else { return emoji(fallback, scale: scale) }
        let sprite = SKSpriteNode(texture: texture)
        // кратное увеличение пикселей: все пиксели одного размера, картинка четкая
        let longest = max(texture.size().width, texture.size().height)
        let side = Pixel.crisp(cellSize * (scale + 0.12), source: longest)
        let k = side / longest
        sprite.size = CGSize(width: texture.size().width * k, height: texture.size().height * k)
        return sprite
    }

    /// Мягкая тень под предметом: он стоит на клетке, а не нарисован на ней.
    private func shadow(width: CGFloat) -> SKNode {
        let e = SKShapeNode(ellipseOf: CGSize(width: cellSize * width, height: cellSize * 0.16))
        e.fillColor = UIColor(red: 0.12, green: 0.2, blue: 0.08, alpha: 0.28)
        e.strokeColor = .clear
        e.position = CGPoint(x: 0, y: -cellSize * 0.3)
        e.zPosition = -0.5
        return e
    }

    private func emoji(_ text: String, scale: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(text: text)
        label.fontSize = cellSize * scale
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }

    /// Номер ступени (или цена) в углу клетки: четкие пиксельные цифры со светлой обводкой.
    private func badge(_ text: String, icon: String? = nil) -> SKNode {
        let node = SKNode()
        let size = max(10, (cellSize * 0.27).rounded())
        func label(_ color: UIColor, dx: CGFloat, dy: CGFloat) -> SKLabelNode {
            let l = SKLabelNode(text: text)
            l.fontName = Pixel.fontName
            l.fontSize = size
            l.fontColor = color
            l.horizontalAlignmentMode = .right
            l.verticalAlignmentMode = .bottom
            l.position = CGPoint(x: dx, y: dy)
            return l
        }
        let o: CGFloat = 1.5
        for (dx, dy) in [(-o, 0), (o, 0), (0, -o), (0, o), (o, -o)] {
            node.addChild(label(Palette.badgeOutline, dx: dx, dy: dy))
        }
        node.addChild(label(Palette.badge, dx: 0, dy: 0))
        node.position = CGPoint(x: cellSize * 0.44, y: -cellSize * 0.44)
        if let icon, let texture = Sprites.texture(icon) {
            let width = CGFloat(text.count) * size * 0.62 + 2
            let side = Pixel.crisp(size * 1.6, source: 16)
            let sprite = SKSpriteNode(texture: texture, size: CGSize(width: side, height: side))
            sprite.position = CGPoint(x: -width - side * 0.4, y: size * 0.5)
            node.addChild(sprite)
        }
        return node
    }

    /// Звезды уровня генератора в верхнем левом углу.
    private func stars(_ count: Int) -> SKNode {
        let node = SKNode()
        guard let texture = Sprites.texture("ui_star") else { return node }
        let side = Pixel.crisp(cellSize * 0.24, source: 16)
        for i in 0..<count {
            let star = SKSpriteNode(texture: texture, size: CGSize(width: side, height: side))
            // больше трех звезд - вторым рядом, чтобы не вылезали за клетку
            star.position = CGPoint(x: -cellSize * 0.36 + CGFloat(i % 3) * side * 0.7, y: cellSize * (i < 3 ? 0.36 : 0.22))
            node.addChild(star)
        }
        node.zPosition = 1
        return node
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
            if let opened = store.lastOpenedChest, opened.index == from {
                store.lastOpenedChest = nil
                openChest(at: from, chest: opened.chest, reward: opened.reward)
            }
            if case .spawned(let cell, _)? = result {
                squish(at: from)
                fly(cell, from: center(of: from))
            } else if case .noEnergy? = result {
                shake(at: from)
            }
            return
        }
        if index(at: p) == nil, p.y < origin.y, store.game.piece(at: from)?.item != nil {
            // брошен ниже поля: в корзину
            if store.storeItem(at: from) {
                forget(from)
                dragged.removeFromParent()
                render()
                return
            }
        }
        guard let to = index(at: p), to != from else {
            // мимо поля или на то же место: предмет плавно возвращается
            dragged.run(.group([.move(to: center(of: from), duration: 0.16), .scale(to: 1, duration: 0.16)])) { [weak self] in
                dragged.zPosition = 1
                self?.render()
            }
            return
        }
        forget(from)
        let result = store.move(from: from, to: to)
        render()
        switch result {
        case .merged(_, let cleared, let bubble):
            pop(at: to)
            sparkle(at: to)
            if store.game.lastLuckyEnergy > 0 { lucky(at: to, energy: store.game.lastLuckyEnergy) }
            for i in cleared { dust(at: i) }
            if let bubble { fly(bubble, from: center(of: to)) }
            for cell in store.game.lastChests { fly(cell, from: center(of: to)) }
        case .mergedGenerator, .mergedChest:
            pop(at: to)
            sparkle(at: to)
        case .unlocked:
            pop(at: to)
            leaves(at: to)
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
        if let from = touchIndex, dragging != nil { forget(from) }
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

    /// Счастливое слияние: золотое кольцо и «+N» с молнией, которые всплывают над клеткой.
    private func lucky(at index: Int, energy: Int) {
        let c = center(of: index)
        let ring = SKShapeNode(circleOfRadius: cellSize * 0.3)
        ring.strokeColor = UIColor(red: 1, green: 0.84, blue: 0.3, alpha: 1)
        ring.lineWidth = 3
        ring.fillColor = .clear
        ring.position = c
        ring.zPosition = 7
        boardNode.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 2, duration: 0.45), .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
        let node = badge("+\(energy)", icon: "ui_energy")
        node.setScale(1.5)
        node.position = CGPoint(x: c.x + cellSize * 0.2, y: c.y + cellSize * 0.1)
        node.zPosition = 8
        node.alpha = 0
        boardNode.addChild(node)
        let rise = SKAction.moveBy(x: 0, y: cellSize * 0.8, duration: 0.9)
        rise.timingMode = .easeOut
        node.run(.sequence([.fadeIn(withDuration: 0.12), .group([rise, .sequence([.wait(forDuration: 0.55), .fadeOut(withDuration: 0.35)])]), .removeFromParent()]))
    }

    /// Листья разлетаются, когда расчищается заросль. Ящик за ряд вылетает из клетки.
    private func leaves(at index: Int) {
        let c = center(of: index)
        for k in 0..<7 {
            let leaf = SKShapeNode(ellipseOf: CGSize(width: cellSize * 0.16, height: cellSize * 0.09))
            leaf.fillColor = k.isMultiple(of: 2) ? Palette.thicketOpen : Palette.thicket
            leaf.strokeColor = .clear
            leaf.position = c
            leaf.zPosition = 6
            boardNode.addChild(leaf)
            let dx = CGFloat.random(in: -0.7...0.7) * cellSize, dy = CGFloat.random(in: 0.2...0.8) * cellSize
            let out = SKAction.moveBy(x: dx, y: dy, duration: 0.35)
            out.timingMode = .easeOut
            let fall = SKAction.moveBy(x: dx * 0.2, y: -cellSize * 0.5, duration: 0.35)
            leaf.run(.sequence([.group([out, .rotate(byAngle: .pi * CGFloat.random(in: -2...2), duration: 0.7),
                                        .sequence([.wait(forDuration: 0.35), .group([fall, .fadeOut(withDuration: 0.35)])])]),
                                .removeFromParent()]))
        }
        guard let store else { return }
        for cell in store.game.lastChests { fly(cell, from: c) }
    }

    /// Ящик открывается: крышка поднимается, награда разлетается.
    func openChest(at index: Int, chest: Chest, reward: ChestReward) {
        let c = center(of: index)
        if chest.kind == .items, let spill = reward.items.first, spill.cell != index {
            // из ящика достали один предмет: ящик подпрыгивает, предмет летит в клетку
            squish(at: index)
            fly(spill.cell, from: c)
            return
        }
        if chest.kind == .items, let tex = Sprites.texture(Self.chestKey(chest, open: true)) {
            let side = Pixel.crisp(cellSize * 0.72, source: 16)
            let lid = SKSpriteNode(texture: tex, size: CGSize(width: side, height: side))
            lid.position = c
            lid.zPosition = 6
            boardNode.addChild(lid)
            lid.run(.sequence([.scale(to: 1.15, duration: 0.12), .wait(forDuration: 0.25),
                               .group([.fadeOut(withDuration: 0.25), .scale(to: 0.7, duration: 0.25)]), .removeFromParent()]))
        }
        sparkle(at: index)
        let gains: [(String, Int)] = [("ui_coin", reward.coins), ("ui_energy", reward.energy), ("ui_gem", reward.gems)]
        for (k, (iconKey, amount)) in gains.enumerated() where amount > 0 {
            let node = badge("+\(amount)", icon: iconKey)
            node.setScale(1.6)
            node.position = CGPoint(x: c.x + cellSize * 0.2, y: c.y + cellSize * (0.1 + CGFloat(k) * 0.3))
            node.zPosition = 8
            node.alpha = 0
            boardNode.addChild(node)
            let rise = SKAction.moveBy(x: 0, y: cellSize, duration: 1.0)
            rise.timingMode = .easeOut
            node.run(.sequence([.fadeIn(withDuration: 0.12), .group([rise, .sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.4)])]), .removeFromParent()]))
        }
        for spill in reward.items { fly(spill.cell, from: c) }
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
    static let thicket = UIColor(red: 0.20, green: 0.36, blue: 0.22, alpha: 1)
    static let thicketOpen = UIColor(red: 0.30, green: 0.48, blue: 0.28, alpha: 1)
    static let chestGlow = UIColor(red: 1, green: 0.9, blue: 0.55, alpha: 0.35)
    static let bubble = UIColor(red: 0.62, green: 0.86, blue: 0.98, alpha: 0.6)
    static let selected = UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)
    static let needed = UIColor(red: 0.85, green: 1.0, blue: 0.6, alpha: 0.75)
    static let badge = UIColor(red: 0.30, green: 0.20, blue: 0.10, alpha: 1)
    static let badgeOutline = UIColor(red: 1.0, green: 0.96, blue: 0.86, alpha: 1)
}
