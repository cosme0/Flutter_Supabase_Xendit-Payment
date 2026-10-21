class Product {
  final int id;
  final String name;
  final num price;
  final String imageUrl;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
  });

  // Converts a raw database Map from Supabase into a safe Dart object
  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] ?? 0,
      name: map['name'] ?? 'Unnamed Item',
      price: map['price'] ?? 0,
      imageUrl: map['image_url'] ?? '',
    );
  }
}