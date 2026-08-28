import SwiftUI
import TokenPetCore

struct CharacterManagerView: View {
    @ObservedObject var model: CharacterManagerModel
    @ObservedObject var languageSettings: LanguageSettings
    @State private var showsDeleteConfirmation = false

    private func t(_ korean: String) -> String { languageSettings.text(korean) }
    private func frameTitle(_ index: Int) -> String { t("프레임") + " " + String(index + 1) }

    var body: some View {
        HSplitView {
            characterList
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 650)
    }

    private var characterList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t("캐릭터"))
                    .font(.title2.bold())
                Spacer()
                Button {
                    model.createCharacter()
                } label: {
                    Image(systemName: "plus")
                }
                .help(t("새 캐릭터"))
            }
            .padding(16)

            Divider()

            List(model.profiles) { profile in
                Button {
                    model.selectProfile(id: profile.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: CharacterRepository.builtInIDs.contains(profile.id) ? "battery.100" : "photo.stack")
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(CharacterRepository.builtInIDs.contains(profile.id) ? t(profile.name) : profile.name)
                                .lineLimit(1)
                            if CharacterRepository.builtInIDs.contains(profile.id) {
                                Text(t("기본 · 읽기 전용"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(String(profile.frameCount) + " " + t("프레임"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if model.selectedID == profile.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    model.selectedID == profile.id
                        ? Color.accentColor.opacity(0.14)
                        : Color.clear
                )
            }
            .listStyle(.sidebar)

            Divider()
            Button(t("새 캐릭터 추가")) {
                model.createCharacter()
            }
            .buttonStyle(.borderedProminent)
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var editor: some View {
        if let draft = model.draft {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    editorHeader(draft: draft)
                    Divider()
                    frameSection(draft: draft)
                    Divider()
                    previewSection(draft: draft)
                    Divider()
                    actionBar
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let builtInPreview = model.builtInPreview {
            builtInEditor(builtInPreview)
        } else {
            VStack(spacing: 18) {
                Image(systemName: "battery.100")
                    .font(.system(size: 70))
                    .foregroundStyle(.tint)
                Text(t("기본 캐릭터"))
                    .font(.title.bold())
                Text(t("기본 캐릭터는 읽기 전용입니다.\n새 캐릭터를 추가하거나 왼쪽 목록에서 편집할 캐릭터를 선택하세요."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(t("새 캐릭터 추가")) {
                    model.createCharacter()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func builtInEditor(_ character: RuntimeCharacter) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(t(character.profile.name))
                    .font(.title.bold())
                Text(t("기본 · 읽기 전용"))
                    .foregroundStyle(.secondary)
                Text(t("기본 캐릭터의 이미지와 이름은 보호됩니다. 퍼센트 위치만 직접 조절할 수 있습니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                ForEach(character.frames.indices, id: \.self) { index in
                    Button {
                        model.selectFrame(index: index)
                    } label: {
                        VStack(spacing: 5) {
                            Image(nsImage: character.frames[index])
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .padding(6)
                            Text(frameTitle(index))
                                .font(.caption.bold())
                        }
                        .frame(width: 110, height: 120)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(model.selectedFrameIndex == index ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: model.selectedFrameIndex == index ? 3 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 26) {
                if character.frames.indices.contains(model.selectedFrameIndex),
                   let position = model.selectedFramePosition {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(frameTitle(model.selectedFrameIndex) + " " + t("위치 편집"))
                            .font(.headline)
                        Text(t("선택한 이미지에서 72%를 드래그하세요."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        CharacterFramePositionEditor(
                            image: character.frames[model.selectedFrameIndex],
                            position: position,
                            fontSize: character.profile.percentFontSize,
                            onPositionChange: model.updateSelectedFramePercentPosition
                        )
                        .frame(width: 300, height: 300)
                        .background(checkerboard)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.25)))
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text(frameTitle(model.selectedFrameIndex) + " " + t("좌표"))
                            .font(.headline)
                        numericField(
                            title: "X",
                            value: position.x,
                            range: 0...1,
                            onChange: { model.updateSelectedFramePercentPosition(.init(x: $0, y: model.selectedFramePosition?.y ?? 0.5)) }
                        )
                        numericField(
                            title: "Y",
                            value: position.y,
                            range: 0...1,
                            onChange: { model.updateSelectedFramePercentPosition(.init(x: model.selectedFramePosition?.x ?? 0.5, y: $0)) }
                        )
                        Text(t("글자 크기") + " " + String(Int(character.profile.percentFontSize.rounded())) + "pt")
                        Slider(
                            value: Binding(
                                get: { character.profile.percentFontSize },
                                set: { model.updateFontSize($0) }
                            ),
                            in: 10...36,
                            step: 1
                        )
                        .frame(width: 220)
                    }
                    .padding(.top, 48)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func editorHeader(draft: CharacterDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("캐릭터 설정"))
                .font(.title2.bold())
            TextField(
                t("캐릭터 이름"),
                text: Binding(
                    get: { draft.name },
                    set: { model.updateName($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 420)
        }
    }

    private func frameSection(draft: CharacterDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("애니메이션 프레임"))
                        .font(.headline)
                    Text(t("PNG/JPG 이미지 3장 또는 4장을 선택하고 드래그해 순서를 바꾸세요."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(t("이미지 선택…")) {
                    model.importFrames()
                }
            }

            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    frameTile(draft: draft, index: index)
                }
            }

            Toggle(
                t("밝은 배경 제거"),
                isOn: Binding(
                    get: { draft.removesLightBackground },
                    set: { model.setRemovesLightBackground($0) }
                )
            )
            .disabled(draft.sourceFrames.isEmpty)
        }
    }

    @ViewBuilder
    private func frameTile(draft: CharacterDraft, index: Int) -> some View {
        if draft.displayFrames.indices.contains(index), let image = NSImage(data: draft.displayFrames[index]) {
            Button {
                model.selectFrame(index: index)
            } label: {
                VStack(spacing: 7) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(8)
                    Text(frameTitle(index))
                        .font(.caption.bold())
                }
                .frame(width: 120, height: 130)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            model.selectedFrameIndex == index ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: model.selectedFrameIndex == index ? 3 : 1
                        )
                )
            }
            .buttonStyle(.plain)
            .draggable(String(index))
            .dropDestination(for: String.self) { sourceIndices, _ in
                guard let value = sourceIndices.first, let sourceIndex = Int(value) else { return false }
                model.moveFrame(from: sourceIndex, to: index)
                return true
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.title2)
                Text(frameTitle(index))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(width: 120, height: 130)
            .background(Color.secondary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5])))
        }
    }

    private func previewSection(draft: CharacterDraft) -> some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text(frameTitle(model.selectedFrameIndex) + " " + t("위치 편집"))
                    .font(.headline)
                Text(t("선택한 이미지에서 72%를 드래그하세요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if draft.displayFrames.indices.contains(model.selectedFrameIndex),
                   let image = NSImage(data: draft.displayFrames[model.selectedFrameIndex]),
                   let position = model.selectedFramePosition {
                    CharacterFramePositionEditor(
                        image: image,
                        position: position,
                        fontSize: draft.percentFontSize
                    ) { position in
                        model.updateSelectedFramePercentPosition(position)
                    }
                    .frame(width: 300, height: 300)
                    .background(checkerboard)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.25)))
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(t("전체 애니메이션"))
                    .font(.headline)
                Text(t("각 이미지의 위치가 3fps 왕복 재생에 적용됩니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CharacterAnimationPreview(draft: draft)
                    .frame(width: 180, height: 180)
                    .background(checkerboard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))

                Text(frameTitle(model.selectedFrameIndex) + " " + t("좌표"))
                    .font(.headline)
                HStack {
                    numericField(
                        title: "X",
                        value: model.selectedFramePosition?.x ?? 0.5,
                        range: 0...1,
                        onChange: { model.updateSelectedFramePercentPosition(.init(x: $0, y: model.selectedFramePosition?.y ?? 0.5)) }
                    )
                    numericField(
                        title: "Y",
                        value: model.selectedFramePosition?.y ?? 0.5,
                        range: 0...1,
                        onChange: { model.updateSelectedFramePercentPosition(.init(x: model.selectedFramePosition?.x ?? 0.5, y: $0)) }
                    )
                }

                Text(t("글자 크기") + " " + String(Int(draft.percentFontSize.rounded())) + "pt")
                Slider(
                    value: Binding(
                        get: { draft.percentFontSize },
                        set: { model.updateFontSize($0) }
                    ),
                    in: 10...36,
                    step: 1
                )
                .frame(width: 250)
                Text(t("미리보기와 위젯은 같은 위치 계산, 글꼴, 색상과 외곽선을 사용합니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 280, alignment: .leading)
            }
            .padding(.top, 48)
        }
    }

    private func numericField(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
            TextField(
                title,
                value: Binding(
                    get: { value },
                    set: { onChange(min(range.upperBound, max(range.lowerBound, $0))) }
                ),
                format: .number.precision(.fractionLength(2))
            )
            .frame(width: 65)
            .textFieldStyle(.roundedBorder)
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage = model.errorMessage {
                Label(t(errorMessage), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            HStack {
                Button(t("캐릭터 삭제"), role: .destructive) {
                    showsDeleteConfirmation = true
                }
                .disabled(!model.canDeleteSelected)
                Spacer()
                Button(t("취소")) {
                    model.cancelChanges()
                }
                Button(t("저장 및 적용")) {
                    model.saveAndApply()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .confirmationDialog(
            t("이 캐릭터를 삭제할까요?"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("삭제"), role: .destructive) {
                model.deleteSelected()
            }
            Button(t("취소"), role: .cancel) {}
        } message: {
            Text(t("저장된 이미지와 설정이 함께 삭제되며 되돌릴 수 없습니다."))
        }
    }

    private var checkerboard: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            Canvas { context, size in
                let cell: CGFloat = 16
                for row in 0..<Int(ceil(size.height / cell)) {
                    for column in 0..<Int(ceil(size.width / cell)) where (row + column).isMultiple(of: 2) {
                        context.fill(
                            Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                            with: .color(.secondary.opacity(0.08))
                        )
                    }
                }
            }
        }
    }
}

private struct CharacterFramePositionEditor: View {
    let image: NSImage
    let position: NormalizedPoint
    let fontSize: Double
    let onPositionChange: (NormalizedPoint) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                PercentAttributedPreview(
                    position: position,
                    fontSize: fontSize * max(0.01, min(geometry.size.width, geometry.size.height) / 120)
                )
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                        onPositionChange(
                            PercentLayout.clampedPosition(
                                NormalizedPoint(
                                    x: Double(value.location.x / geometry.size.width),
                                    y: 1.0 - Double(value.location.y / geometry.size.height)
                                )
                            )
                        )
                    }
            )
        }
    }
}

private struct CharacterAnimationPreview: View {
    let draft: CharacterDraft

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / Double(FrameSequence.framesPerSecond))) { timeline in
            GeometryReader { geometry in
                ZStack {
                    if let frame = currentFrame(at: timeline.date) {
                        Image(nsImage: frame.image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        PercentAttributedPreview(
                            position: frame.position,
                            fontSize: draft.percentFontSize * max(0.01, min(geometry.size.width, geometry.size.height) / 120)
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func currentFrame(at date: Date) -> (image: NSImage, position: NormalizedPoint)? {
        let sequence = FrameSequence.indices(frameCount: draft.displayFrames.count)
        guard !sequence.isEmpty else { return nil }
        let tick = max(0, Int(date.timeIntervalSinceReferenceDate * Double(FrameSequence.framesPerSecond)))
        let frameIndex = sequence[tick % sequence.count]
        guard draft.displayFrames.indices.contains(frameIndex),
              draft.framePercentPositions.indices.contains(frameIndex),
              let image = NSImage(data: draft.displayFrames[frameIndex]) else { return nil }
        return (image, draft.framePercentPositions[frameIndex])
    }

}

private struct PercentAttributedPreview: NSViewRepresentable {
    let position: NormalizedPoint
    let fontSize: Double

    func makeNSView(context: Context) -> PercentAttributedPreviewView {
        PercentAttributedPreviewView()
    }

    func updateNSView(_ nsView: PercentAttributedPreviewView, context: Context) {
        nsView.position = position
        nsView.fontSize = fontSize
        nsView.needsDisplay = true
    }
}

private final class PercentAttributedPreviewView: NSView {
    var position = NormalizedPoint(x: 0.5, y: 0.5)
    var fontSize: Double = 22
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        PercentTextDrawing.draw(
            text: "72%",
            in: bounds,
            position: position,
            fontSize: fontSize
        )
    }
}
