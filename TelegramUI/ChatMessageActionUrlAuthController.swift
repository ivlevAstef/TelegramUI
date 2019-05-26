import Foundation
import SwiftSignalKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore

private final class ChatMessageActionUrlAuthContentActionNode: HighlightableButtonNode {
    private let backgroundNode: ASDisplayNode
    
    let action: TextAlertAction
    
    init(theme: AlertControllerTheme, action: TextAlertAction) {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.alpha = 0.0
        
        self.action = action
        
        super.init()
        
        self.titleNode.maximumNumberOfLines = 2
        
        self.highligthedChanged = { [weak self] value in
            if let strongSelf = self {
                if value {
                    if strongSelf.backgroundNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    }
                    strongSelf.backgroundNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backgroundNode.alpha = 1.0
                } else if !strongSelf.backgroundNode.alpha.isZero {
                    strongSelf.backgroundNode.alpha = 0.0
                    strongSelf.backgroundNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25)
                }
            }
        }
        
        self.updateTheme(theme)
    }
    
    func updateTheme(_ theme: AlertControllerTheme) {
        self.backgroundNode.backgroundColor = theme.highlightedItemColor
        
        var font = Font.regular(17.0)
        var color = theme.accentColor
        switch self.action.type {
        case .defaultAction, .genericAction:
            break
        case .destructiveAction:
            color = theme.destructiveColor
        }
        switch self.action.type {
        case .defaultAction:
            font = Font.semibold(17.0)
        case .destructiveAction, .genericAction:
            break
        }
        self.setAttributedTitle(NSAttributedString(string: self.action.title, font: font, textColor: color, paragraphAlignment: .center), for: [])
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.addTarget(self, action: #selector(self.pressed), forControlEvents: .touchUpInside)
    }
    
    @objc func pressed() {
        self.action.action()
    }
    
    override func layout() {
        super.layout()
        
        self.backgroundNode.frame = self.bounds
    }
}

private let textFont = Font.regular(13.0)
private let boldTextFont = Font.semibold(13.0)

private func formattedText(_ text: String, color: UIColor, textAlignment: NSTextAlignment = .natural) -> NSAttributedString {
    return parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: textFont, textColor: color), bold: MarkdownAttributeSet(font: boldTextFont, textColor: color), link: MarkdownAttributeSet(font: textFont, textColor: color), linkAttribute: { _ in return nil}), textAlignment: textAlignment)
}

private final class ChatMessageActionUrlAuthAlertContentNode: AlertContentNode {
    private let strings: PresentationStrings
    private let defaultUrl: String
    private let domain: String
    private let bot: Peer
    private let displayName: String
    
    private let titleNode: ASTextNode
    private let textNode: ASTextNode
    private let authorizeCheckNode: CheckNode
    private let authorizeLabelNode: ASTextNode
    private let allowWriteCheckNode: CheckNode
    private let allowWriteLabelNode: ASTextNode
    
    private let actionNodesSeparator: ASDisplayNode
    private let actionNodes: [ChatMessageActionUrlAuthContentActionNode]
    private let actionVerticalSeparators: [ASDisplayNode]
    
    private var validLayout: CGSize?
    
    override var dismissOnOutsideTap: Bool {
        return self.isUserInteractionEnabled
    }
    
    var authorize: Bool = true {
        didSet {
            self.authorizeCheckNode.setIsChecked(self.authorize, animated: true)
            if !self.authorize && self.allowWriteAccess {
                self.allowWriteAccess = false
            }
        }
    }
    
    var allowWriteAccess: Bool = true {
        didSet {
            self.allowWriteCheckNode.setIsChecked(self.allowWriteAccess, animated: true)
            if !self.authorize && self.allowWriteAccess {
                self.authorize = true
            }
        }
    }
    
    init(theme: AlertControllerTheme, ptheme: PresentationTheme, strings: PresentationStrings, defaultUrl: String, domain: String, bot: Peer, requestWriteAccess: Bool, displayName: String, actions: [TextAlertAction]) {
        self.strings = strings
        self.defaultUrl = defaultUrl
        self.domain = domain
        self.bot = bot
        self.displayName = displayName
        
        self.titleNode = ASTextNode()
        self.titleNode.maximumNumberOfLines = 2
        
        self.textNode = ASTextNode()
        self.textNode.maximumNumberOfLines = 0
        
        self.authorizeCheckNode = CheckNode(strokeColor: theme.separatorColor, fillColor: theme.accentColor, foregroundColor: .white, style: .plain)
        self.authorizeCheckNode.setIsChecked(true, animated: false)
        self.authorizeLabelNode = ASTextNode()
        self.authorizeLabelNode.maximumNumberOfLines = 2
        
        self.allowWriteCheckNode = CheckNode(strokeColor: theme.separatorColor, fillColor: theme.accentColor, foregroundColor: .white, style: .plain)
        self.allowWriteCheckNode.setIsChecked(true, animated: false)
        self.allowWriteLabelNode = ASTextNode()
        self.allowWriteLabelNode.maximumNumberOfLines = 2
        
        self.actionNodesSeparator = ASDisplayNode()
        self.actionNodesSeparator.isLayerBacked = true
        
        self.actionNodes = actions.map { action -> ChatMessageActionUrlAuthContentActionNode in
            return ChatMessageActionUrlAuthContentActionNode(theme: theme, action: action)
        }
        
        var actionVerticalSeparators: [ASDisplayNode] = []
        if actions.count > 1 {
            for _ in 0 ..< actions.count - 1 {
                let separatorNode = ASDisplayNode()
                separatorNode.isLayerBacked = true
                actionVerticalSeparators.append(separatorNode)
            }
        }
        self.actionVerticalSeparators = actionVerticalSeparators
        
        super.init()
        
        self.addSubnode(self.titleNode)
        self.addSubnode(self.textNode)
        self.addSubnode(self.authorizeCheckNode)
        self.addSubnode(self.authorizeLabelNode)
        
        if requestWriteAccess {
            self.addSubnode(self.allowWriteCheckNode)
            self.addSubnode(self.allowWriteLabelNode)
        }
        
        self.addSubnode(self.actionNodesSeparator)
        
        for actionNode in self.actionNodes {
            self.addSubnode(actionNode)
        }
        
        for separatorNode in self.actionVerticalSeparators {
            self.addSubnode(separatorNode)
        }
        
        self.authorizeCheckNode.addTarget(target: self, action: #selector(self.authorizePressed))
        self.allowWriteCheckNode.addTarget(target: self, action: #selector(self.allowWritePressed))
        
        self.updateTheme(theme)
    }
    
    @objc private func authorizePressed() {
        self.authorize = !self.authorize
    }
    
    @objc private func allowWritePressed() {
        self.allowWriteAccess = !self.allowWriteAccess
    }
    
    override func updateTheme(_ theme: AlertControllerTheme) {
        self.titleNode.attributedText = NSAttributedString(string: strings.Conversation_OpenBotLinkTitle, font: Font.bold(17.0), textColor: theme.primaryColor, paragraphAlignment: .center)
        
        self.textNode.attributedText = formattedText(strings.Conversation_OpenBotLinkText(self.defaultUrl).0, color: theme.primaryColor, textAlignment: .center)
        self.authorizeLabelNode.attributedText = formattedText(strings.Conversation_OpenBotLinkLogin(self.domain, self.displayName).0, color: theme.primaryColor)
        self.allowWriteLabelNode.attributedText = formattedText(strings.Conversation_OpenBotLinkAllowMessages(self.bot.displayTitle).0, color: theme.primaryColor)
        
        self.actionNodesSeparator.backgroundColor = theme.separatorColor
        for actionNode in self.actionNodes {
            actionNode.updateTheme(theme)
        }
        for separatorNode in self.actionVerticalSeparators {
            separatorNode.backgroundColor = theme.separatorColor
        }
        
        if let size = self.validLayout {
            _ = self.updateLayout(size: size, transition: .immediate)
        }
    }
    
    override func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        var size = size
        size.width = min(size.width, 270.0)
        
        self.validLayout = size
        
        var origin: CGPoint = CGPoint(x: 0.0, y: 20.0)
        
        let titleSize = self.titleNode.measure(size)
        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - titleSize.width) / 2.0), y: origin.y), size: titleSize))
        origin.y += titleSize.height + 9.0
        
        let textSize = self.textNode.measure(size)
        transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - textSize.width) / 2.0), y: origin.y), size: textSize))
        origin.y += textSize.height + 16.0
        
        let checkSize = CGSize(width: 32.0, height: 32.0)
        let condensedSize = CGSize(width: size.width - 76.0, height: size.height)
        
        var entriesHeight: CGFloat = 0.0
        
        let authorizeSize = self.authorizeLabelNode.measure(condensedSize)
        transition.updateFrame(node: self.authorizeLabelNode, frame: CGRect(origin: CGPoint(x: 46.0, y: origin.y), size: authorizeSize))
        transition.updateFrame(node: self.authorizeCheckNode, frame: CGRect(origin: CGPoint(x: 7.0, y: origin.y - 7.0), size: checkSize))
        origin.y += authorizeSize.height
        entriesHeight += authorizeSize.height
        
        if self.allowWriteLabelNode.supernode != nil {
            origin.y += 16.0
            entriesHeight += 16.0
            
            let allowWriteSize = self.allowWriteLabelNode.measure(condensedSize)
            transition.updateFrame(node: self.allowWriteLabelNode, frame: CGRect(origin: CGPoint(x: 46.0, y: origin.y), size: allowWriteSize))
            transition.updateFrame(node: self.allowWriteCheckNode, frame: CGRect(origin: CGPoint(x: 7.0, y: origin.y - 7.0), size: checkSize))
            origin.y += allowWriteSize.height
            entriesHeight += allowWriteSize.height
        }
        
        let actionButtonHeight: CGFloat = 44.0
        var minActionsWidth: CGFloat = 0.0
        let maxActionWidth: CGFloat = floor(size.width / CGFloat(self.actionNodes.count))
        let actionTitleInsets: CGFloat = 8.0
        
        var effectiveActionLayout = TextAlertContentActionLayout.horizontal
        for actionNode in self.actionNodes {
            let actionTitleSize = actionNode.titleNode.measure(CGSize(width: maxActionWidth, height: actionButtonHeight))
            if case .horizontal = effectiveActionLayout, actionTitleSize.height > actionButtonHeight * 0.6667 {
                effectiveActionLayout = .vertical
            }
            switch effectiveActionLayout {
                case .horizontal:
                    minActionsWidth += actionTitleSize.width + actionTitleInsets
                case .vertical:
                    minActionsWidth = max(minActionsWidth, actionTitleSize.width + actionTitleInsets)
            }
        }
        
        let insets = UIEdgeInsets(top: 18.0, left: 18.0, bottom: 18.0, right: 18.0)
        
        var contentWidth = max(titleSize.width, minActionsWidth)
        contentWidth = max(contentWidth, 234.0)
        
        var actionsHeight: CGFloat = 0.0
        switch effectiveActionLayout {
        case .horizontal:
            actionsHeight = actionButtonHeight
        case .vertical:
            actionsHeight = actionButtonHeight * CGFloat(self.actionNodes.count)
        }
        
        let resultWidth = contentWidth + insets.left + insets.right
        let resultSize = CGSize(width: resultWidth, height: titleSize.height + textSize.height + entriesHeight + actionsHeight + 30.0 + insets.top + insets.bottom)
        
        transition.updateFrame(node: self.actionNodesSeparator, frame: CGRect(origin: CGPoint(x: 0.0, y: resultSize.height - actionsHeight - UIScreenPixel), size: CGSize(width: resultSize.width, height: UIScreenPixel)))
        
        var actionOffset: CGFloat = 0.0
        let actionWidth: CGFloat = floor(resultSize.width / CGFloat(self.actionNodes.count))
        var separatorIndex = -1
        var nodeIndex = 0
        for actionNode in self.actionNodes {
            if separatorIndex >= 0 {
                let separatorNode = self.actionVerticalSeparators[separatorIndex]
                switch effectiveActionLayout {
                    case .horizontal:
                        transition.updateFrame(node: separatorNode, frame: CGRect(origin: CGPoint(x: actionOffset - UIScreenPixel, y: resultSize.height - actionsHeight), size: CGSize(width: UIScreenPixel, height: actionsHeight - UIScreenPixel)))
                    case .vertical:
                        transition.updateFrame(node: separatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: resultSize.height - actionsHeight + actionOffset - UIScreenPixel), size: CGSize(width: resultSize.width, height: UIScreenPixel)))
                }
            }
            separatorIndex += 1
            
            let currentActionWidth: CGFloat
            switch effectiveActionLayout {
                case .horizontal:
                    if nodeIndex == self.actionNodes.count - 1 {
                        currentActionWidth = resultSize.width - actionOffset
                    } else {
                        currentActionWidth = actionWidth
                    }
                case .vertical:
                    currentActionWidth = resultSize.width
            }
            
            let actionNodeFrame: CGRect
            switch effectiveActionLayout {
                case .horizontal:
                    actionNodeFrame = CGRect(origin: CGPoint(x: actionOffset, y: resultSize.height - actionsHeight), size: CGSize(width: currentActionWidth, height: actionButtonHeight))
                    actionOffset += currentActionWidth
                case .vertical:
                    actionNodeFrame = CGRect(origin: CGPoint(x: 0.0, y: resultSize.height - actionsHeight + actionOffset), size: CGSize(width: currentActionWidth, height: actionButtonHeight))
                    actionOffset += actionButtonHeight
            }
            
            transition.updateFrame(node: actionNode, frame: actionNodeFrame)
            
            nodeIndex += 1
        }
        
        return resultSize
    }
}

func chatMessageActionUrlAuthController(context: AccountContext, defaultUrl: String, domain: String, bot: Peer, requestWriteAccess: Bool, displayName: String, open: @escaping (Bool, Bool) -> Void) -> AlertController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let theme = presentationData.theme
    let strings = presentationData.strings
    
    var contentNode: ChatMessageActionUrlAuthAlertContentNode?
    
    var dismissImpl: ((Bool) -> Void)?
    let actions: [TextAlertAction] = [TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
        dismissImpl?(true)
    }), TextAlertAction(type: .defaultAction, title: presentationData.strings.Conversation_OpenBotLinkOpen, action: {
        dismissImpl?(true)
        if let contentNode = contentNode {
            open(contentNode.authorize, contentNode.allowWriteAccess)
        }
    })]
    contentNode = ChatMessageActionUrlAuthAlertContentNode(theme: AlertControllerTheme(presentationTheme: theme), ptheme: theme, strings: strings, defaultUrl: defaultUrl, domain: domain, bot: bot, requestWriteAccess: requestWriteAccess, displayName: displayName, actions: actions)
    let controller = AlertController(theme: AlertControllerTheme(presentationTheme: theme), contentNode: contentNode!)
    dismissImpl = { [weak controller] animated in
        if animated {
            controller?.dismissAnimated()
        } else {
            controller?.dismiss()
        }
    }
    return controller
}