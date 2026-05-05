//
//  DocumentCollection+CoreDataProperties.swift
//  
//
//  Created by Adam KZ on 05/05/2026.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias DocumentCollectionCoreDataPropertiesSet = NSSet

extension DocumentCollection {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DocumentCollection> {
        return NSFetchRequest<DocumentCollection>(entityName: "DocumentCollection")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var icon: String?
    @NSManaged public var sortOrder: Int32
    @NSManaged public var kind: String?
    @NSManaged public var ruleDefinition: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var documents: NSSet?
    @NSManaged public var notes: NSSet?
    @NSManaged public var parentCollection: DocumentCollection?
    @NSManaged public var childCollections: NSSet?

}

// MARK: Generated accessors for documents
extension DocumentCollection {

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
extension DocumentCollection {

    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: Note)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: Note)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)

}

// MARK: Generated accessors for childCollections
extension DocumentCollection {

    @objc(addChildCollectionsObject:)
    @NSManaged public func addToChildCollections(_ value: DocumentCollection)

    @objc(removeChildCollectionsObject:)
    @NSManaged public func removeFromChildCollections(_ value: DocumentCollection)

    @objc(addChildCollections:)
    @NSManaged public func addToChildCollections(_ values: NSSet)

    @objc(removeChildCollections:)
    @NSManaged public func removeFromChildCollections(_ values: NSSet)

}

extension DocumentCollection : Identifiable {

}
