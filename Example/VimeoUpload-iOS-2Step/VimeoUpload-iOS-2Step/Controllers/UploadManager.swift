//
//  UploadManager.swift
//  VimeoUpload
//
//  Created by Alfred Hanssen on 10/18/15.
//  Copyright © 2015 Vimeo. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

class UploadManager: NSObject, NSCoding
{
    static let sharedInstance = UploadManager()
    
    // MARK: 
    
    private static let BackgroundSessionIdentifier = "com.vimeo.upload"
    private static let DescriptorManagerName = "uploader"
    private static let AuthToken = "caf4648129ec56e580175c4b45cce7fc"
    
    // MARK: 
    
    private let sessionManager: VimeoSessionManager
    private let descriptorManager: DescriptorManager
    private let deletionManager: DeletionManager
    private let reporter: UploadReporter = UploadReporter()

    // MARK:

    private var failedDescriptors: [String: SimpleUploadDescriptor] = [:]
    
    // MARK:
    
    // MARK: Initialization
    
    deinit
    {
        self.removeObservers()
    }
    
    override init()
    {
        self.sessionManager = VimeoSessionManager.backgroundSessionManager(identifier: UploadManager.BackgroundSessionIdentifier, authToken: UploadManager.AuthToken)
        self.descriptorManager = DescriptorManager(sessionManager: self.sessionManager, name: UploadManager.DescriptorManagerName, delegate: self.reporter)
        self.deletionManager = DeletionManager(sessionManager: ForegroundSessionManager.sharedInstance, retryCount: 2)
     
        super.init()
        
        self.addObservers()
    }
    
    // MARK: Public API
    
    func applicationDidFinishLaunching()
    {
        // Do nothing at the moment
    }
    
    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: VoidBlock) -> Bool
    {
        return self.descriptorManager.handleEventsForBackgroundURLSession(identifier, completionHandler: completionHandler)
    }
    
    func uploadVideo(url url: NSURL, uploadTicket: VIMUploadTicket)
    {
        let descriptor = SimpleUploadDescriptor(url: url, uploadTicket: uploadTicket)
        descriptor.identifier = uploadTicket.video!.uri
        
        self.descriptorManager.addDescriptor(descriptor)
    }
    
    func deleteUpload(videoUri videoUri: String)
    {
        if let descriptor = self.uploadDescriptorForVideo(videoUri: videoUri)
        {
            descriptor.cancel(self.sessionManager)
        }
        
        // TODO: do we need to remove from failed descriptor list here?
        
        self.deletionManager.deleteVideoWithUri(videoUri)
    }

    func uploadDescriptorForVideo(videoUri videoUri: String) -> SimpleUploadDescriptor?
    {
        // Check active descriptors
        var descriptor = self.descriptorManager.descriptorPassingTest({ (descriptor) -> Bool in
            
            if let descriptor = descriptor as? SimpleUploadDescriptor, let currentVideoUri = descriptor.uploadTicket.video?.uri
            {
                return videoUri == currentVideoUri
            }
            
            return false
        })
        
        // Then check failed descriptors
        if descriptor == nil
        {
            descriptor = self.failedDescriptors[videoUri]
        }
        
        return descriptor as? SimpleUploadDescriptor
    }
    
    // MARK: Notifications
    
    private func addObservers()
    {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "descriptorDidFail:", name: DescriptorManagerNotification.DescriptorDidFail.rawValue, object: nil)
    }
    
    private func removeObservers()
    {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func descriptorDidFail(notification: NSNotification)
    {
        // TODO: Do we need to check if it was cancelled?
        
        if let descriptor = notification.object as? SimpleUploadDescriptor, let videoUri = descriptor.uploadTicket.video?.uri
        {
            self.failedDescriptors[videoUri] = descriptor
        }
    }
    
    // MARK: NSCoding
    
    required init(coder aDecoder: NSCoder)
    {
        self.sessionManager = VimeoSessionManager.backgroundSessionManager(identifier: UploadManager.BackgroundSessionIdentifier, authToken: UploadManager.AuthToken)
        self.descriptorManager = DescriptorManager(sessionManager: self.sessionManager, name: UploadManager.DescriptorManagerName, delegate: self.reporter)
        self.deletionManager = DeletionManager(sessionManager: ForegroundSessionManager.sharedInstance, retryCount: 2)

        self.failedDescriptors = aDecoder.decodeObjectForKey("failedDescriptors") as! [String: SimpleUploadDescriptor]
    }
    
    func encodeWithCoder(aCoder: NSCoder)
    {
        aCoder.encodeObject(self.failedDescriptors, forKey: "failedDescriptors")
    }
}
