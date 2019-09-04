# DHT

A [Swift][swift] package to help use the [BitTorrent][bittorrent] [Distributed Hash Table][dht].

## Usage

### Swift Package Manager

Add this package to your `Package.swift` `dependencies` and target's `dependencies`:

```swift
import PackageDescription

let package = Package(
    name: "Example",
    dependencies: [
        .package(
            url: "https://github.com/bluk/DHT",
            from: "0.1.0"
        ),
    ],
    targets: [
        .target(
            name: "YourProject",
            dependencies: ["DHT"]
        )
    ]
)
```

## License

[Apache-2.0 License][license]

[license]: LICENSE
[swift]: https://swift.org
[bittorrent]: http://bittorrent.org/
[dht]: http://bittorrent.org/beps/bep_0005.html
