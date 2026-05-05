//
//  Annotation+CoreDataProperties.swift
//  
//
//  Created by Adam KZ on 28/02/2026.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias AnnotationCoreDataPropertiesSet = NSSet

extension Annotation {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Annotation> {
        return NSFetchRequest<Annotation>(entityName: "Annotation")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var kind: String?
    @NSManaged public var colorCategory: String?
    @NSManaged public var pageIndex: Int32
    @NSManaged public var rects: Data?
    @NSManaged public var textSnippet: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var document: Document?
    @NSManaged public var note: Note?
    @NSManaged public var tags: NSSet?

}

// MARK: Generated accessors for tags
extension Annotation {

    @objc(addTagsObject:)
    @NSManaged public func addToTags(_ value: Tag)

    @objc(removeTagsObject:)
    @NSManaged public func removeFromTags(_ value: Tag)

    @objc(addTags:)
    @NSManaged public func addToTags(_ values: NSSet)

    @objc(removeTags:)
    @NSManaged public func removeFromTags(_ values: NSSet)

}

extension Annotation : Identifiable {

}
