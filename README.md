# AppReviews
Tool to fetch review comments from AppStore.

### Apple Store Review comments
To fetch review comments from apple store RSS feeds.
```swift
// Review Comments for "Xcode app" 
ReviewComments.fetchReviews(app: "497799835", country: "us", pageNo: "1", format: "json") { resposne in
    if case .success(let reviews) = resposne {
        // to get feeds from next page.
        ReviewComments.fetchNextReviewPage(app: reviews) { resposne in
            if case .success(let feed) = resposne {
                print(feed)
            }
        }
    }
}
```

### Note:
Working on XML data parsing.
