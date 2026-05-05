//
//  Document+CoreDataProperties.swift
//  
//
//  Created by Adam KZ on 05/05/2026.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias DocumentCoreDataPropertiesSet = NSSet

extension Document {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Document> {
        return NSFetchRequest<Document>(entityName: "Document")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var subtitle: String?
    @NSManaged public var authors: [String]?
    @NSManaged public var source: String?
    @NSManaged public var publicationDate: Date?
    @NSManaged public var keywords: [String]?
    @NSManaged public var checksum: String?
    @NSManaged public var fileURL: URL?
    @NSManaged public var pageCount: Int32
    @NSManaged public var ocrStatus: String?
    @NSManaged public var documentType: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var annotations: NSSet?
    @NSManaged public var notes: NSSet?
    @NSManaged public var collections: NSSet?
    @NSManaged public var tags: NSSet?
    @NSManaged public var attachments: NSSet?

}

// MARK: Generated accessors for annotations
extension Document {

    @objc(addAnnotationsObject:)
    @NSManaged public func addToAnnotations(_ value: Annotation)

    @objc(removeAnnotationsObject:)
    @NSManaged public func removeFromAnnotations(_ value: Annotation)

    @objc(addAnnotations:)
    @NSManaged public func addToAnnotations(_ values: NSSet)

    @objc(removeAnnotations:)
    @NSManaged public func removeFromAnnotations(_ values: NSSet)

}

// MARK: Generated accessors for notes
extension Document {

    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: Note)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: Note)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)

}

// MARK: Generated accessors for collections
extension Document {

    @objc(addCollectionsObject:)
    @NSManaged public func addToCollections(_ value: DocumentCollection)

    @objc(removeCollectionsObject:)
    @NSManaged public func removeFromCollections(_ value: DocumentCollection)

    @objc(addCollections:)
    @NSManaged public func addToCollections(_ values: NSSet)

    @objc(removeCollections:)
    @NSManaged public func removeFromCollections(_ values: NSSet)

}

// MARK: Generated accessors for tags
extension Document {

    @objc(addTagsObject:)
    @NSManaged public func addToTags(_ value: Tag)

    @objc(removeTagsObject:)
    @NSManaged public func removeFromTags(_ value: Tag)

    @objc(addTags:)
    @NSManaged public func addToTags(_ values: NSSet)

    @objc(removeTags:)
    @NSManaged public func removeFromTags(_ values: NSSet)

}

// MARK: Generated accessors for attachments
extension Document {

    @objc(addAttachmentsObject:)
    @NSManaged public func addToAttachments(_ value: Attachment)

    @objc(removeAttachmentsObject:)
    @NSManaged public func removeFromAttachments(_ value: Attachment)

    @objc(addAttachments:)
    @NSManaged public func addToAttachments(_ values: NSSet)

    @objc(removeAttachments:)
    @NSManaged public func removeFromAttachments(_ values: NSSet)

}

extension Document : Identifiable {

}
