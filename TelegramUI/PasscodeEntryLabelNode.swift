import Foundation
import AsyncDisplayKit
import Display

enum PasscodeEntryTitleAnimation {
    case none
    case slideIn
    case crossFade
}

final class PasscodeEntryLabelNode: ASDisplayNode {
    private let wrapperNode: ASDisplayNode
    private let textNode: ASTextNode
    
    private var validLayout: ContainerViewLayout?
    
    override init() {
        self.wrapperNode = ASDisplayNode()
        self.wrapperNode.clipsToBounds = true
        
        self.textNode = ASTextNode()
        self.textNode.isLayerBacked = false
        
        super.init()
        
        self.addSubnode(self.wrapperNode)
        self.wrapperNode.addSubnode(self.textNode)
    }
    
    func setAttributedText(_ text: NSAttributedString, animation: PasscodeEntryTitleAnimation = .none, completion: @escaping () -> Void = {}) {
        switch animation {
            case .none:
                self.textNode.attributedText = text
                completion()
            
                if let validLayout = self.validLayout {
                    let _ = self.updateLayout(layout: validLayout, transition: .immediate)
                }
            case .slideIn:
                self.textNode.attributedText = text
                if let validLayout = self.validLayout {
                    let _ = self.updateLayout(layout: validLayout, transition: .immediate)
                }
            
                let offset = self.wrapperNode.bounds.width / 2.0
                self.wrapperNode.layer.animatePosition(from: CGPoint(x: -offset, y: 0.0), to: CGPoint(), duration: 0.45, additive: true)
                self.textNode.layer.animatePosition(from: CGPoint(x: offset * 2.0, y: 0.0), to: CGPoint(), duration: 0.45, additive: true, completion: { _ in
                    completion()
                })
                self.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
            case .crossFade:
                if let snapshotView = self.textNode.view.snapshotContentTree() {
                    snapshotView.frame = self.textNode.frame
                    self.textNode.view.superview?.insertSubview(snapshotView, aboveSubview: self.textNode.view)
                    self.textNode.alpha = 0.0
                    snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                        snapshotView?.removeFromSuperview()
                        self.textNode.attributedText = text
                        self.textNode.alpha = 1.0
                        self.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3, completion: { _ in
                            completion()
                        })
                        if let validLayout = self.validLayout {
                            let _ = self.updateLayout(layout: validLayout, transition: .immediate)
                        }
                    })
                } else {
                    self.textNode.attributedText = text
                    self.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
                    completion()
                    if let validLayout = self.validLayout {
                        let _ = self.updateLayout(layout: validLayout, transition: .immediate)
                    }
                }
        }
    }
    
    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) -> CGSize {
        self.validLayout = layout
        
        let textSize = self.textNode.measure(layout.size)
        let textFrame = CGRect(x: floor((layout.size.width - textSize.width) / 2.0), y: 0.0, width: textSize.width, height: textSize.height)
        transition.updateFrame(node: self.wrapperNode, frame: textFrame)
        transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(), size: textSize))
        
        return CGSize(width: layout.size.width, height: 25.0)
    }
}
