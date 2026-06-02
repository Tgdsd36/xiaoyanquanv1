bool isPaidMemberType(String memberType) {
  switch (memberType) {
    case 'pro':
    case 'professional':
    case 'flagship':
      return true;
    default:
      return false;
  }
}

String memberBadgeLabel(String memberType) {
  switch (memberType) {
    case 'professional':
      return '专业版';
    case 'pro':
    case 'flagship':
      return 'Pro';
    default:
      return 'Free';
  }
}

bool shouldShowMemberExpiry(String memberType) {
  return isPaidMemberType(memberType);
}
