//
//  Tag+CoreDataProperties.swift
//  
//
//  Created by Adam KZ on 28/02/2026.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias TagCoreDataPropertiesSet = NSSet

extension Tag {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Tag> {
        return NSFetchRequest<Tag>(entityName: "Tag")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var color: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var parentTag: Tag?
    @NSManaged public var childTags: NSSet?
    @NSManaged public var documents: NSSet?
    @NSManaged public var notes: NSSet?
    @NSManaged public var annotations: NSSet?

}

// MARK: Generated accessors for childTags
extension Tag {

    @objc(addChildTagsObject:)
    @NSManaged public func addToChildTags(_ value: Tag)

    @objc(removeChildTagsObject:)
    @NSManaged public func removeFromChildTags(_ value: Tag)

    @objc(addChildTags:)
    @NSManaged public func addToChildTags(_ values: NSSet)

    @objc(removeChildTags:)
    @NSManaged public func removeFromChildTags(_ values: NSSet)

}

// MARK: Generated accessors for documents
extension Tag {

    @objc(addDocumentsObject:)
    @NSManaged public func addToDocuments(_ value: Document)

    @objc(removeDocumentsObject:)
    @NSManaged public func removeFromDocuments(_ value: Document)

    @objc(addDocuments:)
    @NSManaged public func addToDocuments(_ values: NSSet)

    @objc(removeDocuments:)
    @NSManaged public func removeFromDocuments(_ values: NSSet)

}

// MARK: Generated accessors for notes
extension Tag {

    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: Note)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: Note)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)

}

// MARK: Generated accessors for annotations
extension Tag {

    @objc(addAnnotationsObject:)
    @NSManaged public func addToAnnotations(_ value: Annotation)

    @objc(removeAnnotationsObject:)
    @NSManaged public func removeFromAnnotations(_ value: Annotation)

    @objc(addAnnotations:)
    @NSManaged public func addToAnnotations(_ values: NSSet)

    @objc(removeAnnotations:)
    @NSManaged public func removeFromAnnotations(_ values: NSSet)

}

extension Tag : Identifiable {

}
