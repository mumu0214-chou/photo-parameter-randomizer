import AppKit
import Foundation
import UniformTypeIdentifiers

struct CameraProfile {
    let model: String
    let tele: Int
    let mainFocal: Double
    let teleFocal: Double
}
struct Settings {
    let model: String
    let lens: String
    let aperture: Double
    let equivalent: Int
    let focal: Double
    let lensModel: String
    let iso: Int
    let shutterDenominator: Int
    let light: String
}
enum ImageToolError: LocalizedError {
    case process(String)
    case missingTool
    var errorDescription: String? {
        switch self {
        case .process(let message): return message
        case .missingTool: return "应用组件缺失，请重新下载完整应用。"
        }
    }
}
let profiles = [CameraProfile(model: "iPhone 14 Pro", tele: 77, mainFocal: 6.86, teleFocal: 9.0), CameraProfile(model: "iPhone 15 Pro", tele: 77, mainFocal: 6.86, teleFocal: 9.0), CameraProfile(model: "iPhone 16 Pro", tele: 120, mainFocal: 6.765, teleFocal: 15.66)]
let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]

func randomSettings(modelChoice: Int, lensChoice: Int, lightChoice: Int) -> Settings {
    let profile = modelChoice == 0 ? profiles.randomElement()! : profiles[modelChoice - 1]
    let chosenLens: Int = lensChoice == 0 ? ([1, 1, 1, 1, 2, 3].randomElement()!) : lensChoice
    let lens: (String, Double, Int, Double)
    switch chosenLens {
    case 2: lens = ("超广角", 2.2, 13, 2.22)
    case 3: lens = ("长焦", 2.8, profile.tele, profile.teleFocal)
    default: lens = ("主摄", 1.78, 24, profile.mainFocal)
    }
    let condition = lightChoice == 0 ? Int.random(in: 1...3) : lightChoice
    let choices: [(Int, Int)]
    let light: String
    switch condition {
    case 1:
        light = "明亮"
        choices = [(32,1000),(40,800),(50,1000),(50,640),(64,800),(80,500),(100,640),(125,1000),(160,500)]
    case 2:
        light = "室内"
        choices = [(50,125),(64,100),(80,125),(100,100),(125,100),(160,80),(200,100),(250,60),(320,80),(400,60)]
    default:
        light = "较暗"
        choices = [(200,40),(320,40),(400,30),(500,40),(640,30),(800,25),(1000,30),(1250,20)]
    }
    let exposure = choices.randomElement()!
    let lensName: String
    switch chosenLens {
    case 2: lensName = "超广角摄像头"
    case 3: lensName = "长焦摄像头"
    default: lensName = "主摄像头"
    }
    let lensModel = "\(lensName) — \(lens.2) mm ƒ\(lens.1)"
    return Settings(model: profile.model, lens: lens.0, aperture: lens.1, equivalent: lens.2, focal: lens.3, lensModel: lensModel, iso: exposure.0, shutterDenominator: exposure.1, light: light)
}

func runTool(_ arguments: [String]) throws -> String {
    guard let path = Bundle.main.resourcePath.map({ $0 + "/exiftool/exiftool" }), FileManager.default.isReadableFile(atPath: path) else { throw ImageToolError.missingTool }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    task.arguments = [path] + arguments
    let output = Pipe()
    task.standardOutput = output
    task.standardError = output
    try task.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    let text = String(data: data, encoding: .utf8) ?? ""
    if task.terminationStatus != 0 { throw ImageToolError.process(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
    return text
}

func writeImage(input: URL, output: URL, settings: Settings) throws {
    guard input.standardizedFileURL != output.standardizedFileURL else { throw ImageToolError.process("输出不能覆盖原图。") }
    guard !FileManager.default.fileExists(atPath: output.path) else { throw ImageToolError.process("输出文件已存在。") }
    let result = try runTool([
        "-charset", "exif=UTF8", "-EXIF:Make=Apple", "-EXIF:Model=\(settings.model)", "-EXIF:ISO=\(settings.iso)",
        "-EXIF:ExposureTime=1/\(settings.shutterDenominator)", "-EXIF:FNumber=\(settings.aperture)",
        "-EXIF:FocalLengthIn35mmFormat=\(settings.equivalent)", "-EXIF:FocalLength=\(settings.focal)", "-EXIF:LensModel=\(settings.lensModel)", "-EXIF:LensMake=Apple",
        "-o", output.path, input.path
    ])
    if !FileManager.default.fileExists(atPath: output.path) { throw ImageToolError.process("未生成输出文件：\(result)") }
    let raw = try runTool(["-charset", "exif=UTF8", "-j", "-n", "-EXIF:Make", "-EXIF:Model", "-EXIF:ISO", "-EXIF:ExposureTime", "-EXIF:FNumber", "-EXIF:FocalLength", "-EXIF:FocalLengthIn35mmFormat", "-EXIF:LensModel", "-EXIF:LensMake", output.path])
    guard let bytes = raw.data(using: .utf8),
          let items = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]], let v = items.first,
          (v["Make"] as? String) == "Apple", (v["Model"] as? String) == settings.model,
          (v["ISO"] as? NSNumber)?.intValue == settings.iso,
          abs(((v["ExposureTime"] as? NSNumber)?.doubleValue ?? 0) - 1.0 / Double(settings.shutterDenominator)) < 0.000001,
          abs(((v["FNumber"] as? NSNumber)?.doubleValue ?? 0) - settings.aperture) < 0.0001,
          (v["FocalLengthIn35mmFormat"] as? NSNumber)?.intValue == settings.equivalent,
          abs(((v["FocalLength"] as? NSNumber)?.doubleValue ?? 0) - settings.focal) < 0.0001,
          (v["LensModel"] as? String) == settings.lensModel,
          (v["LensMake"] as? String) == "Apple"
    else { throw ImageToolError.process("写入后核对失败，请检查输出文件：\(output.lastPathComponent)") }
}

func uniqueDestination(for input: URL, directory: URL) -> URL {
    var base = input.deletingPathExtension().lastPathComponent
    if let range = base.range(of: "_模拟参数(?=(_[0-9]+)?$)", options: .regularExpression) {
        base.removeSubrange(range)
        if base.isEmpty { base = input.deletingPathExtension().lastPathComponent }
    }
    let ext = input.pathExtension
    var suffix = 0
    while true {
        let stem = suffix == 0 ? base : "\(base)_\(suffix + 1)"
        let candidate = directory.appendingPathComponent(stem).appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        suffix += 1
    }
}

final class DropZone: NSView {
    var onDrop: (([URL]) -> Void)?
    private var isHovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("拖入图片或文件夹")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        (isHovering ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isHovering ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        path.stroke()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let title = "把图片或文件夹拖到这里"
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style]
        title.draw(in: NSRect(x: 0, y: bounds.midY - 1, width: bounds.width, height: 20), withAttributes: titleAttributes)
        "支持 JPG、PNG、WebP，可一次拖入多张".draw(in: NSRect(x: 0, y: bounds.midY - 20, width: bounds.width, height: 17), withAttributes: subtitleAttributes)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        isHovering = true; needsDisplay = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { isHovering = false; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHovering = false; needsDisplay = true
        return acceptPasteboard(sender.draggingPasteboard)
    }
    func acceptPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = NSPopUpButton()
    let lens = NSPopUpButton()
    let light = NSPopUpButton()
    let selectedLabel = NSTextField(labelWithString: "尚未选择图片")
    let outputLabel = NSTextField(wrappingLabelWithString: "")
    let progressLabel = NSTextField(labelWithString: "")
    let log = NSTextView()
    let startButton = NSButton(title: "开始处理", target: nil, action: nil)
    let openButton = NSButton(title: "打开结果文件夹", target: nil, action: nil)
    var inputs: [URL] = []
    var outputDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/图片参数处理结果", isDirectory: true)
    var processing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 760), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "图片参数随机生成器"
        window.center()
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28), root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28), root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22), root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -22)])
        func row(_ views: [NSView]) -> NSStackView { let s = NSStackView(views: views); s.orientation = .horizontal; s.spacing = 10; s.alignment = .centerY; return s }
        func button(_ title: String, _ action: Selector) -> NSButton { let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; return b }
        let title = NSTextField(labelWithString: "图片参数随机生成器")
        title.font = NSFont.systemFont(ofSize: 23, weight: .bold)
        let description = NSTextField(wrappingLabelWithString: "为 AI 图片添加模拟相机参数。批量处理，每张独立随机；生成新副本，原图不变。")
        description.textColor = .secondaryLabelColor
        description.font = NSFont.systemFont(ofSize: 13)
        root.addArrangedSubview(title); root.addArrangedSubview(description)
        let dropZone = DropZone()
        dropZone.onDrop = { [weak self] urls in self?.addDropped(urls) }
        root.addArrangedSubview(dropZone)
        dropZone.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        dropZone.heightAnchor.constraint(equalToConstant: 70).isActive = true
        root.addArrangedSubview(row([button("选择图片…", #selector(selectImages)), button("选择文件夹…", #selector(selectFolder)), button("清空", #selector(clearImages))]))
        selectedLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        root.addArrangedSubview(selectedLabel)
        model.addItems(withTitles: ["随机型号", "iPhone 14 Pro", "iPhone 15 Pro", "iPhone 16 Pro"])
        lens.addItems(withTitles: ["随机镜头（主摄为主）", "主摄", "超广角", "长焦"])
        light.addItems(withTitles: ["随机光线", "明亮", "室内", "较暗"])
        root.addArrangedSubview(row([NSTextField(labelWithString: "机型"), model, NSTextField(labelWithString: "镜头"), lens]))
        root.addArrangedSubview(row([NSTextField(labelWithString: "曝光范围"), light]))
        let notes = NSTextField(wrappingLabelWithString: "光圈和等效焦距随镜头匹配；ISO 与快门按所选光线范围随机。参数为模拟值，不会改变画面。")
        notes.textColor = .secondaryLabelColor; notes.font = NSFont.systemFont(ofSize: 12)
        root.addArrangedSubview(notes)
        root.addArrangedSubview(row([button("选择输出位置…", #selector(selectOutput)), openButton]))
        outputLabel.font = NSFont.systemFont(ofSize: 12); outputLabel.textColor = .secondaryLabelColor
        updateOutputLabel(); root.addArrangedSubview(outputLabel)
        startButton.target = self; startButton.action = #selector(start); startButton.bezelStyle = .rounded; startButton.keyEquivalent = "\r"
        openButton.target = self; openButton.action = #selector(openOutput); openButton.bezelStyle = .rounded
        root.addArrangedSubview(row([startButton, progressLabel]))
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        log.isEditable = false; log.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        log.string = "支持 JPG、PNG、WebP；可多选图片或选择文件夹。\n\n结果会保存在桌面的“图片参数处理结果”文件夹，也可以自行选择保存位置。\n\n如原图含数字来源凭证，写入元数据可能影响其验证状态。"
        scroll.documentView = log
        root.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        outputLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        notes.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        description.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func updateOutputLabel() { outputLabel.stringValue = "保存到：\(outputDir.path)" }
    func addDropped(_ urls: [URL]) {
        guard !processing else { return }
        var images: [URL] = []
        var errors: [String] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                do {
                    let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                    images += children.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                } catch { errors.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            } else { images.append(url) }
        }
        let before = inputs.count
        addInputs(images)
        if !errors.isEmpty { showError("部分文件夹无法读取：\n" + errors.joined(separator: "\n")) }
        else if inputs.count == before { showError("没有新增图片。支持 JPG、PNG 和 WebP；文件夹只读取第一层。") }
    }
    func addInputs(_ urls: [URL]) {
        var known = Set(inputs.map { $0.standardizedFileURL.path })
        for url in urls where supportedExtensions.contains(url.pathExtension.lowercased()) {
            let p = url.standardizedFileURL.path
            if known.insert(p).inserted { inputs.append(url) }
        }
        selectedLabel.stringValue = inputs.isEmpty ? "尚未选择图片" : "已选择 \(inputs.count) 张图片"
        if !inputs.isEmpty { log.string = inputs.map { $0.lastPathComponent }.joined(separator: "\n") }
    }
    @objc func selectImages() {
        guard !processing else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.jpeg, UTType.png, UTType.webP]
        if panel.runModal() == .OK { addInputs(panel.urls) }
    }
    @objc func selectFolder() {
        guard !processing else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do { addInputs(try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) }
            catch { showError("读取文件夹失败：\(error.localizedDescription)") }
        }
    }
    @objc func clearImages() { guard !processing else { return }; inputs = []; selectedLabel.stringValue = "尚未选择图片"; log.string = "" }
    @objc func selectOutput() {
        guard !processing else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { outputDir = url; updateOutputLabel() }
    }
    @objc func openOutput() {
        if FileManager.default.fileExists(atPath: outputDir.path) { NSWorkspace.shared.open(outputDir) }
        else { showError("结果文件夹尚未创建，请先处理图片。") }
    }
    func showError(_ text: String) { let alert = NSAlert(); alert.messageText = text; alert.runModal() }
    @objc func start() {
        guard !processing else { return }
        guard !inputs.isEmpty else { showError("请先选择图片。 "); return }
        do { try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true) }
        catch { showError("无法创建输出文件夹：\(error.localizedDescription)"); return }
        let source = inputs, directory = outputDir, m = model.indexOfSelectedItem, l = lens.indexOfSelectedItem, c = light.indexOfSelectedItem
        processing = true; startButton.isEnabled = false; progressLabel.stringValue = "正在处理…"; log.string = ""
        DispatchQueue.global(qos: .userInitiated).async {
            var successes = 0, failures = 0, messages: [String] = []
            for input in source {
                let config = randomSettings(modelChoice: m, lensChoice: l, lightChoice: c)
                let output = uniqueDestination(for: input, directory: directory)
                do {
                    try writeImage(input: input, output: output, settings: config)
                    successes += 1
                    messages.append("✓ \(output.lastPathComponent)\n   \(config.model) · \(config.lens) · \(config.light)\n   ISO \(config.iso) · 1/\(config.shutterDenominator) 秒 · f/\(config.aperture) · 等效 \(config.equivalent) mm")
                } catch {
                    failures += 1
                    messages.append("✗ \(input.lastPathComponent)：\(error.localizedDescription)")
                }
                let count = successes + failures
                let snapshot = messages.joined(separator: "\n\n")
                DispatchQueue.main.async { self.progressLabel.stringValue = "\(count)/\(source.count)"; self.log.string = snapshot }
            }
            let finalSuccess = successes, finalFailures = failures
            DispatchQueue.main.async {
                self.processing = false; self.startButton.isEnabled = true
                self.progressLabel.stringValue = "完成：\(finalSuccess) 张成功，\(finalFailures) 张失败"
            }
        }
    }
}

if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--test-dest" {
    let result = uniqueDestination(for: URL(fileURLWithPath: CommandLine.arguments[2]), directory: URL(fileURLWithPath: CommandLine.arguments[3]))
    print(result.lastPathComponent)
} else if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--test-drop" {
    guard CommandLine.arguments.count > 2 else { fputs("Usage: --test-drop path...\n", stderr); exit(2) }
    _ = NSApplication.shared
    let delegate = AppDelegate()
    let zone = DropZone(frame: NSRect(x: 0, y: 0, width: 200, height: 70))
    zone.onDrop = { delegate.addDropped($0) }
    let board = NSPasteboard(name: NSPasteboard.Name("local.codex.drop-test.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let urls = CommandLine.arguments.dropFirst(2).map { URL(fileURLWithPath: $0) as NSURL }
    guard board.writeObjects(urls), zone.acceptPasteboard(board) else { fputs("Drop failed\n", stderr); exit(1) }
    print(delegate.inputs.map { $0.lastPathComponent }.sorted().joined(separator: "\n"))
} else if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--test-write" {
    guard CommandLine.arguments.count == 4 || CommandLine.arguments.count == 7 else { fputs("Usage: --test-write input output [model lens light]\n", stderr); exit(2) }
    let choices: [Int] = CommandLine.arguments.count == 7 ? CommandLine.arguments[4...6].map { Int($0) ?? -1 } : [0, 0, 0]
    guard choices.allSatisfy({ (0...3).contains($0) }) else { fputs("Invalid choice\n", stderr); exit(2) }
    let s = randomSettings(modelChoice: choices[0], lensChoice: choices[1], lightChoice: choices[2])
    do { try writeImage(input: URL(fileURLWithPath: CommandLine.arguments[2]), output: URL(fileURLWithPath: CommandLine.arguments[3]), settings: s); print("\(s.model), \(s.lens), ISO \(s.iso), 1/\(s.shutterDenominator), f/\(s.aperture), \(s.equivalent)mm") }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
