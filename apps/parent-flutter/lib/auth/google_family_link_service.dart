class FamilyMember {
  final String name;
  final String email;
  final String? profilePhotoUrl;

  const FamilyMember({
    required this.name,
    required this.email,
    this.profilePhotoUrl,
  });
}

class GoogleFamilyLinkService {
  static Future<List<FamilyMember>> fetchChildren(String parentEmail) async {
    // Simulates querying the Google supervised family group endpoints (kid.family scope)
    await Future.delayed(const Duration(milliseconds: 600)); // Simulate API network latency
    
    if (parentEmail.toLowerCase() == 'stefanheintz@gmail.com') {
      return [
        const FamilyMember(name: 'Felix', email: 'felix.heintz@gmail.com'),
      ];
    } else {
      return [
        const FamilyMember(name: 'Felix', email: 'felix@gmail.com'),
        const FamilyMember(name: 'Emma', email: 'emma@gmail.com'),
      ];
    }
  }
}
