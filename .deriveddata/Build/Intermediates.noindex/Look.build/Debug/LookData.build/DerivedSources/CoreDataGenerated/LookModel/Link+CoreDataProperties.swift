//
//  Link+CoreDataProperties.swift
//  
//
//  Created by Adam KZ on 26/02/2026.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias LinkCoreDataPropertiesSet = NSSet

extension Link {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Link> {
        return NSFetchRequest<Link>(entityName: "Link")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var kind: String?
    @NSManaged public var displayText: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var sourceNote: Note?
    @NSManaged public var targetNote: Note?

}

extension Link : Identifiable {

}
