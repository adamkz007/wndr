//
//  Attachment+CoreDataProperties.swift
//  
//
//  Created by Adam KZ on 05/05/2026.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias AttachmentCoreDataPropertiesSet = NSSet

extension Attachment {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Attachment> {
        return NSFetchRequest<Attachment>(entityName: "Attachment")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var filename: String?
    @NSManaged public var type: String?
    @NSManaged public var fileURL: URL?
    @NSManaged public var createdAt: Date?
    @NSManaged public var note: Note?
    @NSManaged public var document: Document?

}

extension Attachment : Identifiable {

}
