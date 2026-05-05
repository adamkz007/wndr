//
//  Note+CoreDataProperties.swift
//  
//
//  Created by Adam KZ on 05/05/2026.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias NoteCoreDataPropertiesSet = NSSet

extension Note {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Note> {
        return NSFetchRequest<Note>(entityName: "Note")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var body: String?
    @NSManaged public var frontMatter: [String: String]?
    @NSManaged public var pinned: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var document: Document?
    @NSManaged public var annotations: NSSet?
    @NSManaged public var attachments: NSSet?
    @NSManaged public var tags: NSSet?
    @NSManaged public var outgoingLinks: NSSet?
    @NSManaged public var incomingLinks: NSSet?
    @NSManaged public var collections: NSSet?

}

// MARK: Generated accessors for annotations
extension Note {

    @objc(addAnnotationsObject:)
    @NSManaged public func addToAnnotations(_ value: Annotation)

    @objc(removeAnnotationsObject:)
    @NSManaged public func removeFromAnnotations(_ value: Annotation)

    @objc(addAnnotations:)
    @NSManaged public func addToAnnotations(_ values: NSSet)

    @objc(removeAnnotations:)
    @NSManaged public func removeFromAnnotations(_ values: NSSet)

}

// MARK: Generated accessors for attachments
extension Note {

    @objc(addAttachmentsObject:)
    @NSManaged public func addToAttachments(_ value: Attachment)

    @objc(removeAttachmentsObject:)
    @NSManaged public func removeFromAttachments(_ value: Attachment)

    @objc(addAttachments:)
    @NSManaged public func addToAttachments(_ values: NSSet)

    @objc(removeAttachments:)
    @NSManaged public func removeFromAttachments(_ values: NSSet)

}

// MARK: Generated accessors for tags
extension Note {

    @objc(addTagsObject:)
    @NSManaged public func addToTags(_ value: Tag)

    @objc(removeTagsObject:)
    @NSManaged public func removeFromTags(_ value: Tag)

    @objc(addTags:)
    @NSManaged public func addToTags(_ values: NSSet)

    @objc(removeTags:)
    @NSManaged public func removeFromTags(_ values: NSSet)

}

// MARK: Generated accessors for outgoingLinks
extension Note {

    @objc(addOutgoingLinksObject:)
    @NSManaged public func addToOutgoingLinks(_ value: Link)

    @objc(removeOutgoingLinksObject:)
    @NSManaged public func removeFromOutgoingLinks(_ value: Link)

    @objc(addOutgoingLinks:)
    @NSManaged public func addToOutgoingLinks(_ values: NSSet)

    @objc(removeOutgoingLinks:)
    @NSManaged public func removeFromOutgoingLinks(_ values: NSSet)

}

// MARK: Generated accessors for incomingLinks
extension Note {

    @objc(addIncomingLinksObject:)
    @NSManaged public func addToIncomingLinks(_ value: Link)

    @objc(removeIncomingLinksObject:)
    @NSManaged public func removeFromIncomingLinks(_ value: Link)

    @objc(addIncomingLinks:)
    @NSManaged public func addToIncomingLinks(_ values: NSSet)

    @objc(removeIncomingLinks:)
    @NSManaged public func removeFromIncomingLinks(_ values: NSSet)

}

// MARK: Generated accessors for collections
extension Note {

    @objc(addCollectionsObject:)
    @NSManaged public func addToCollections(_ value: DocumentCollection)

    @objc(removeCollectionsObject:)
    @NSManaged public func removeFromCollections(_ value: DocumentCollection)

    @objc(addCollections:)
    @NSManaged public func addToCollections(_ values: NSSet)

    @objc(removeCollections:)
    @NSManaged public func removeFromCollections(_ values: NSSet)

}

extension Note : Identifiable {

}
