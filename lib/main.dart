import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin.dart';
import 'database.dart';
import 'espace_motard.dart';
import 'localisation.dart';
import 'models/course.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.initialize();
  runApp(const ThiakThiakApp());
}

const couleurFond = Color(0xFF101820);
const couleurCarte = Color(0xFF1D2935);
const couleurOrange = Color(0xFFFF9F43);
const couleurTexte = Color(0xFFF5F5F5);

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Application
// ---------------------------------------------------------------------------

class ThiakThiakApp extends StatelessWidget {
  const ThiakThiakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thiak-Thiak',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: couleurFond,
        colorScheme: ColorScheme.fromSeed(
          seedColor: couleurOrange,
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: couleurCarte,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        useMaterial3: true,
      ),
      home: const _ApplicationGate(),
    );
  }
}

class _ApplicationGate extends StatelessWidget {
  const _ApplicationGate();

  @override
  Widget build(BuildContext context) {
    if (!DatabaseService.isConfigured) return const RacinePage();

    final client = DatabaseService.client;
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = client.auth.currentSession;
        if (session == null) return const ConnexionClientPage();
        return RacinePage(key: ValueKey(session.user.id));
      },
    );
  }
}

class ConnexionClientPage extends StatefulWidget {
  const ConnexionClientPage({super.key});

  @override
  State<ConnexionClientPage> createState() => _ConnexionClientPageState();
}

class _ConnexionClientPageState extends State<ConnexionClientPage> {
  final _telephoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _codeEnvoye = false;
  bool _envoi = false;

  @override
  void dispose() {
    _telephoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String? _telephoneInternational() {
    var telephone = _telephoneCtrl.text.replaceAll(RegExp(r'[\s().-]'), '');
    if (telephone.startsWith('+221')) {
      telephone = telephone.substring(4);
    } else if (telephone.startsWith('00221')) {
      telephone = telephone.substring(5);
    }
    if (!RegExp(r'^7[05678]\d{7}$').hasMatch(telephone)) return null;
    return '+221$telephone';
  }

  Future<void> _envoyerCode() async {
    final telephone = _telephoneInternational();
    if (telephone == null) {
      afficherMessage(context, 'Indiquez un numéro sénégalais valide.');
      return;
    }
    setState(() => _envoi = true);
    try {
      await DatabaseService.client.auth.signInWithOtp(phone: telephone);
      if (!mounted) return;
      setState(() => _codeEnvoye = true);
      afficherMessage(context, 'Code de vérification envoyé par SMS.');
    } on AuthException catch (error) {
      if (mounted) afficherMessage(context, error.message);
    } on Exception catch (error) {
      if (mounted) afficherMessage(context, messageErreurBaseDeDonnees(error));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _verifierCode() async {
    final telephone = _telephoneInternational();
    final code = _codeCtrl.text.trim();
    if (telephone == null || code.isEmpty) {
      afficherMessage(context, 'Saisissez le numéro et le code reçu.');
      return;
    }
    setState(() => _envoi = true);
    try {
      await DatabaseService.client.auth.verifyOTP(
        phone: telephone,
        token: code,
        type: OtpType.sms,
      );
    } on AuthException catch (error) {
      if (mounted) afficherMessage(context, error.message);
    } on Exception catch (error) {
      if (mounted) afficherMessage(context, messageErreurBaseDeDonnees(error));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: couleurFond,
        title: const Text('Connexion'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.sms_outlined, color: couleurOrange, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Connectez-vous avec votre téléphone',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: couleurTexte,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _telephoneCtrl,
                keyboardType: TextInputType.phone,
                enabled: !_codeEnvoye && !_envoi,
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                  hintText: '+221 77 123 45 67',
                  prefixIcon: Icon(Icons.phone_outlined, color: couleurOrange),
                ),
              ),
              if (_codeEnvoye) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Code reçu par SMS',
                    prefixIcon: Icon(Icons.lock_outline, color: couleurOrange),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _envoi
                    ? null
                    : _codeEnvoye
                    ? _verifierCode
                    : _envoyerCode,
                child: Text(
                  _envoi
                      ? 'Veuillez patienter...'
                      : _codeEnvoye
                      ? 'Vérifier le code'
                      : 'Recevoir un code',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RacinePage extends StatefulWidget {
  const RacinePage({super.key});

  @override
  State<RacinePage> createState() => _RacinePageState();
}

class _RacinePageState extends State<RacinePage> {
  int _index = 0;
  final List<Course> _courses = [];
  final _database = const DatabaseRepository();

  @override
  void initState() {
    super.initState();
    if (DatabaseService.isConfigured) _chargerCourses();
  }

  Future<void> _chargerCourses() async {
    try {
      final courses = await _database.loadCourses();
      if (mounted) {
        setState(
          () => _courses
            ..clear()
            ..addAll(courses),
        );
      }
    } on Exception catch (error) {
      if (mounted) afficherMessage(context, messageErreurBaseDeDonnees(error));
    }
  }

  Future<void> _ouvrirCommande(TypeCourse type) async {
    final course = await Navigator.of(
      context,
    ).push<Course>(MaterialPageRoute(builder: (_) => CommandePage(type: type)));
    if (course != null && mounted) {
      if (DatabaseService.isConfigured) {
        try {
          await _database.createCourse(course);
        } on Exception catch (error) {
          if (mounted) {
            afficherMessage(context, messageErreurBaseDeDonnees(error));
          }
          return;
        }
        if (!mounted) return;
      }
      setState(() {
        _courses.insert(0, course);
        _index = 1;
      });
      afficherMessage(
        context,
        DatabaseService.isConfigured
            ? 'Course enregistrée dans votre compte.'
            : 'Course en mode démo : elle ne sera pas synchronisée.',
      );
    }
  }

  void _ouvrirInscriptionMotard() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const InscriptionMotardPage()));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      AccueilPage(
        onCommander: () => _ouvrirCommande(TypeCourse.moto),
        onLivraison: () => _ouvrirCommande(TypeCourse.livraison),
        onMotard: _ouvrirInscriptionMotard,
        onProfil: () => setState(() => _index = 2),
      ),
      MesCoursesPage(courses: _courses),
      ComptePage(onDevenirMotard: _ouvrirInscriptionMotard),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: couleurCarte,
        indicatorColor: couleurOrange.withValues(alpha: 0.2),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: couleurOrange),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: couleurOrange),
            label: 'Mes courses',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: couleurOrange),
            label: 'Compte',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Accueil
// ---------------------------------------------------------------------------

class AccueilPage extends StatelessWidget {
  final VoidCallback onCommander;
  final VoidCallback onLivraison;
  final VoidCallback onMotard;
  final VoidCallback onProfil;

  const AccueilPage({
    super.key,
    required this.onCommander,
    required this.onLivraison,
    required this.onMotard,
    required this.onProfil,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: couleurFond,
        title: const Row(
          children: [
            Icon(Icons.two_wheeler, color: couleurOrange, size: 32),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'THIAK-THIAK',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: couleurTexte,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Aperçu sur un Galaxy fictif',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ApercuGalaxyPage())),
            icon: const Icon(Icons.phone_android),
          ),
          IconButton(
            tooltip: 'Profil',
            onPressed: onProfil,
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 15),
              const Text(
                'Bonjour !',
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Où souhaitez-vous aller ?',
                style: TextStyle(
                  color: couleurTexte,
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 25),
              const CarteAccueil(),
              const SizedBox(height: 28),
              const Text(
                'Que voulez-vous faire ?',
                style: TextStyle(
                  color: couleurTexte,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              BoutonService(
                icone: Icons.motorcycle,
                titre: 'Commander une moto',
                description: 'Déplacez-vous rapidement',
                couleur: couleurOrange,
                onTap: onCommander,
              ),
              const SizedBox(height: 14),
              BoutonService(
                icone: Icons.delivery_dining,
                titre: 'Livraison',
                description: 'Envoyez un colis avec un motard',
                couleur: Colors.tealAccent,
                onTap: onLivraison,
              ),
              const SizedBox(height: 14),
              BoutonService(
                icone: Icons.directions_bike,
                titre: 'Devenir motard',
                description: 'Rejoignez notre réseau de conducteurs',
                couleur: Colors.lightBlueAccent,
                onTap: onMotard,
              ),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: couleurCarte,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: couleurOrange, size: 30),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Thiak-Thiak : vos déplacements et livraisons en toute simplicité.',
                        style: TextStyle(color: couleurTexte, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ApercuGalaxyPage extends StatelessWidget {
  const ApercuGalaxyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: couleurFond,
        title: const Text('Aperçu Samsung Galaxy'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < constraints.maxHeight * 0.48
                ? constraints.maxWidth
                : constraints.maxHeight * 0.48;

            return Center(
              child: SizedBox(
                width: width,
                height: width / 0.48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF090B0D),
                    borderRadius: BorderRadius.circular(42),
                    border: Border.all(color: Colors.white24, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(34),
                      child: const _EcranGalaxyFictif(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EcranGalaxyFictif extends StatefulWidget {
  const _EcranGalaxyFictif();

  @override
  State<_EcranGalaxyFictif> createState() => _EcranGalaxyFictifState();
}

class _EcranGalaxyFictifState extends State<_EcranGalaxyFictif> {
  int _onglet = 0;
  TypeCourse? _serviceActif;
  bool _inscriptionMotard = false;
  bool _commandeConfirmee = false;
  final List<Course> _courses = [];

  void _ouvrirService(TypeCourse type) {
    setState(() {
      _serviceActif = type;
      _inscriptionMotard = false;
      _commandeConfirmee = false;
    });
  }

  void _ouvrirInscriptionMotard() {
    setState(() {
      _serviceActif = null;
      _inscriptionMotard = true;
      _commandeConfirmee = false;
    });
  }

  void _retourAccueil() {
    setState(() {
      _serviceActif = null;
      _inscriptionMotard = false;
      _commandeConfirmee = false;
      _onglet = 0;
    });
  }

  void _ajouterCourse(Course course) {
    setState(() {
      _courses.insert(0, course);
      _commandeConfirmee = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget contenu;
    if ((_serviceActif != null || _inscriptionMotard) && !_commandeConfirmee) {
      contenu = _FormulaireGalaxy(
        type: _serviceActif ?? TypeCourse.moto,
        inscriptionMotard: _inscriptionMotard,
        onRetour: _retourAccueil,
        onConfirmer: _ajouterCourse,
        onInscrireMotard: () => setState(() => _commandeConfirmee = true),
      );
    } else if (_commandeConfirmee) {
      contenu = _ConfirmationGalaxy(
        onRetour: _retourAccueil,
        inscriptionMotard: _inscriptionMotard,
      );
    } else if (_onglet == 1) {
      contenu = _CoursesGalaxy(courses: _courses);
    } else if (_onglet == 2) {
      contenu = _CompteGalaxy(
        onDevenirMotard: () {
          _ouvrirInscriptionMotard();
        },
      );
    } else {
      contenu = _EcranAccueilGalaxy(
        onCommander: () => _ouvrirService(TypeCourse.moto),
        onLivraison: () => _ouvrirService(TypeCourse.livraison),
        onMotard: _ouvrirInscriptionMotard,
        onProfil: () => setState(() => _onglet = 2),
      );
    }

    return ColoredBox(
      color: couleurFond,
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Text(
                  '9:41',
                  style: TextStyle(
                    color: couleurTexte,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Positioned(
                  left: 12,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const Positioned(
                  right: 12,
                  child: Icon(
                    Icons.network_cell,
                    size: 13,
                    color: couleurTexte,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: contenu),
          if (_serviceActif == null &&
              !_inscriptionMotard &&
              !_commandeConfirmee)
            Container(
              height: 48,
              decoration: const BoxDecoration(
                color: couleurCarte,
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavigationGalaxy(
                    icone: Icons.home,
                    label: 'Accueil',
                    active: _onglet == 0,
                    onTap: () => setState(() => _onglet = 0),
                  ),
                  _NavigationGalaxy(
                    icone: Icons.receipt_long_outlined,
                    label: 'Courses',
                    active: _onglet == 1,
                    onTap: () => setState(() => _onglet = 1),
                  ),
                  _NavigationGalaxy(
                    icone: Icons.person_outline,
                    label: 'Compte',
                    active: _onglet == 2,
                    onTap: () => setState(() => _onglet = 2),
                  ),
                ],
              ),
            ),
          Container(
            height: 10,
            alignment: Alignment.center,
            color: couleurCarte,
            child: Container(
              width: 76,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white70,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EcranAccueilGalaxy extends StatelessWidget {
  final VoidCallback onCommander;
  final VoidCallback onLivraison;
  final VoidCallback onMotard;
  final VoidCallback onProfil;

  const _EcranAccueilGalaxy({
    required this.onCommander,
    required this.onLivraison,
    required this.onMotard,
    required this.onProfil,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.two_wheeler,
                      color: couleurOrange,
                      size: 23,
                    ),
                    const SizedBox(width: 7),
                    const Expanded(
                      child: Text(
                        'THIAK-THIAK',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: couleurTexte,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Compte',
                      onPressed: onProfil,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      icon: const Icon(
                        Icons.account_circle_outlined,
                        color: couleurTexte,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 19),
                const Text(
                  'Bonjour !',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Où souhaitez-vous aller ?',
                  style: TextStyle(
                    color: couleurTexte,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                Container(
                  height: 105,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: couleurCarte,
                    borderRadius: BorderRadius.circular(17),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF314453), Color(0xFF1D2935)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Stack(
                    children: [
                      Center(
                        child: Icon(
                          Icons.map_outlined,
                          size: 56,
                          color: Colors.white24,
                        ),
                      ),
                      Positioned(
                        right: 35,
                        top: 25,
                        child: Icon(
                          Icons.location_on,
                          color: couleurOrange,
                          size: 34,
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 10,
                        child: Text(
                          'Votre position',
                          style: TextStyle(color: couleurTexte, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 17),
                const Text(
                  'Que voulez-vous faire ?',
                  style: TextStyle(
                    color: couleurTexte,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 9),
                _ServiceGalaxy(
                  icone: Icons.motorcycle,
                  titre: 'Commander une moto',
                  description: 'Déplacez-vous rapidement',
                  couleur: couleurOrange,
                  onTap: onCommander,
                ),
                const SizedBox(height: 8),
                _ServiceGalaxy(
                  icone: Icons.delivery_dining,
                  titre: 'Livraison',
                  description: 'Envoyez un colis',
                  couleur: Colors.tealAccent,
                  onTap: onLivraison,
                ),
                const SizedBox(height: 8),
                _ServiceGalaxy(
                  icone: Icons.directions_bike,
                  titre: 'Devenir motard',
                  description: 'Rejoignez notre réseau',
                  couleur: Colors.lightBlueAccent,
                  onTap: onMotard,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceGalaxy extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String description;
  final Color couleur;
  final VoidCallback onTap;

  const _ServiceGalaxy({
    required this.icone,
    required this.titre,
    required this.description,
    required this.couleur,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: couleurCarte,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: couleur.withValues(alpha: 0.15),
                child: Icon(icone, color: couleur, size: 19),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: couleurTexte,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationGalaxy extends StatelessWidget {
  final IconData icone;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavigationGalaxy({
    required this.icone,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? couleurOrange : Colors.white60;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 65,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, size: 17, color: color),
            Text(label, style: TextStyle(color: color, fontSize: 8)),
          ],
        ),
      ),
    );
  }
}

class _FormulaireGalaxy extends StatefulWidget {
  final TypeCourse type;
  final bool inscriptionMotard;
  final VoidCallback onRetour;
  final ValueChanged<Course> onConfirmer;
  final VoidCallback onInscrireMotard;

  const _FormulaireGalaxy({
    required this.type,
    this.inscriptionMotard = false,
    required this.onRetour,
    required this.onConfirmer,
    required this.onInscrireMotard,
  });

  @override
  State<_FormulaireGalaxy> createState() => _FormulaireGalaxyState();
}

class _FormulaireGalaxyState extends State<_FormulaireGalaxy> {
  final _departCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();

  @override
  void dispose() {
    _departCtrl.dispose();
    _destinationCtrl.dispose();
    super.dispose();
  }

  void _confirmer() {
    if (_departCtrl.text.trim().isEmpty ||
        _destinationCtrl.text.trim().isEmpty) {
      afficherMessage(
        context,
        widget.inscriptionMotard
            ? 'Indiquez votre nom et votre téléphone.'
            : 'Indiquez le départ et la destination.',
      );
      return;
    }
    if (widget.inscriptionMotard) {
      widget.onInscrireMotard();
      return;
    }
    widget.onConfirmer(
      Course(
        type: widget.type,
        depart: _departCtrl.text.trim(),
        destination: _destinationCtrl.text.trim(),
        prixEstime: widget.type == TypeCourse.livraison ? 1500 : 1000,
        date: DateTime.now(),
        statut: 'Commande de démonstration',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final livraison = widget.type == TypeCourse.livraison;
    final inscriptionMotard = widget.inscriptionMotard;
    return Column(
      children: [
        _EnteteGalaxy(
          titre: inscriptionMotard
              ? 'Devenir motard'
              : livraison
              ? 'Nouvelle livraison'
              : 'Commander une moto',
          onRetour: widget.onRetour,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Simulation de démonstration',
                  style: TextStyle(
                    color: couleurTexte,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Remplissez le formulaire pour essayer le parcours.',
                  style: TextStyle(color: Colors.white60, fontSize: 10),
                ),
                const SizedBox(height: 13),
                TextField(
                  controller: _departCtrl,
                  style: const TextStyle(color: couleurTexte, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: inscriptionMotard
                        ? 'Nom complet'
                        : 'Point de départ',
                    labelStyle: const TextStyle(fontSize: 11),
                    prefixIcon: Icon(
                      inscriptionMotard ? Icons.person : Icons.my_location,
                      size: 17,
                    ),
                    prefixIconColor: couleurOrange,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _destinationCtrl,
                  keyboardType: inscriptionMotard
                      ? TextInputType.phone
                      : TextInputType.text,
                  style: const TextStyle(color: couleurTexte, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: inscriptionMotard ? 'Téléphone' : 'Destination',
                    labelStyle: TextStyle(fontSize: 11),
                    prefixIcon: Icon(
                      inscriptionMotard ? Icons.phone : Icons.location_on,
                      size: 17,
                    ),
                    prefixIconColor: couleurOrange,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
                if (!inscriptionMotard) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Prix indicatif : ${livraison ? 1500 : 1000} FCFA',
                    style: const TextStyle(
                      color: couleurOrange,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _confirmer,
                  style: FilledButton.styleFrom(
                    backgroundColor: couleurOrange,
                    foregroundColor: couleurFond,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    inscriptionMotard
                        ? 'Envoyer ma demande'
                        : 'Confirmer la commande',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EnteteGalaxy extends StatelessWidget {
  final String titre;
  final VoidCallback? onRetour;

  const _EnteteGalaxy({required this.titre, this.onRetour});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          if (onRetour != null)
            IconButton(
              onPressed: onRetour,
              icon: const Icon(Icons.arrow_back, color: couleurTexte, size: 17),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 38),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Text(
              titre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: couleurTexte,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ConfirmationGalaxy extends StatelessWidget {
  final VoidCallback onRetour;
  final bool inscriptionMotard;

  const _ConfirmationGalaxy({
    required this.onRetour,
    this.inscriptionMotard = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: couleurOrange, size: 42),
            const SizedBox(height: 10),
            Text(
              inscriptionMotard ? 'Demande simulée !' : 'Commande simulée !',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: couleurTexte,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              inscriptionMotard
                  ? 'Votre inscription de démonstration est prise en compte.'
                  : 'Elle apparaît maintenant dans l’onglet Courses.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetour,
              child: const Text('Retour à l’accueil'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoursesGalaxy extends StatelessWidget {
  final List<Course> courses;

  const _CoursesGalaxy({required this.courses});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EnteteGalaxy(titre: 'Mes courses'),
        Expanded(
          child: courses.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'Aucune course pour le moment.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: courses.length,
                  itemBuilder: (context, index) {
                    final course = courses[index];
                    return Card(
                      color: couleurCarte,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${course.type == TypeCourse.livraison ? 'Livraison' : 'Moto'} • ${course.prixEstime} FCFA',
                              style: const TextStyle(
                                color: couleurOrange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${course.depart} → ${course.destination}',
                              style: const TextStyle(
                                color: couleurTexte,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              course.statut,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CompteGalaxy extends StatelessWidget {
  final VoidCallback onDevenirMotard;

  const _CompteGalaxy({required this.onDevenirMotard});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _EnteteGalaxy(titre: 'Compte'),
        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 27,
                    backgroundColor: couleurCarte,
                    child: Icon(Icons.person, color: couleurOrange, size: 30),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Utilisateur Thiak-Thiak',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: couleurTexte,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Compte de démonstration',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onDevenirMotard,
              child: const Text(
                'Devenir motard',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Commande (moto ou livraison)
// ---------------------------------------------------------------------------

class CommandePage extends StatefulWidget {
  final TypeCourse type;
  const CommandePage({super.key, required this.type});

  @override
  State<CommandePage> createState() => _CommandePageState();
}

class _CommandePageState extends State<CommandePage> {
  static const _texteLieuCommande = 'Lieu de la commande';
  static const _texteCarte = 'Point choisi sur la carte';

  final _formKey = GlobalKey<FormState>();
  final _departCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  LatLng? _departPos;
  LatLng? _lieuCommandePos;
  LatLng? _destPos;
  bool _localisationEnCours = false;
  bool _autreLieuDepart = false;

  bool get _estLivraison => widget.type == TypeCourse.livraison;

  double? get _distanceKm => (_departPos != null && _destPos != null)
      ? ServiceLocalisation.distanceKm(_departPos!, _destPos!)
      : null;

  // Tarif provisoire (FCFA) : base + prix au km, arrondi à 50, avec minimum.
  // À remplacer par le calcul définitif du serveur.
  int get _prix {
    final minimum = _estLivraison ? 1500 : 1000;
    final km = _distanceKm;
    if (km == null) return minimum;
    final base = _estLivraison ? 700 : 500;
    final parKm = _estLivraison ? 250 : 200;
    final arrondi = ((base + parKm * km) / 50).round() * 50;
    return arrondi < minimum ? minimum : arrondi;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _utiliserMaPosition(silencieux: true),
    );
  }

  @override
  void dispose() {
    _departCtrl.dispose();
    _destinationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _utiliserMaPosition({bool silencieux = false}) async {
    if (!mounted) return;
    setState(() => _localisationEnCours = true);
    try {
      final pos = await ServiceLocalisation.positionActuelle();
      if (!mounted) return;
      if (_autreLieuDepart) return;
      setState(() {
        _departPos = pos;
        _lieuCommandePos = pos;
        _departCtrl.text = _texteLieuCommande;
      });
    } on ErreurLocalisation catch (e) {
      if (mounted && !silencieux) afficherMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _localisationEnCours = false);
    }
  }

  void _choisirModeDepart(bool autreLieu) {
    if (_autreLieuDepart == autreLieu) return;
    setState(() {
      _autreLieuDepart = autreLieu;
      _departPos = null;
      _departCtrl.clear();
    });
    if (!autreLieu) _utiliserMaPosition();
  }

  Future<void> _choisirDepartSurCarte() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => SelectionCartePage(
          depart: _lieuCommandePos ?? _destPos,
          pointInitial: _departPos,
          choisirDepart: true,
        ),
      ),
    );
    if (point != null && mounted) {
      setState(() {
        _departPos = point;
        _departCtrl.text = _texteCarte;
      });
    }
  }

  Future<void> _choisirSurCarte() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) =>
            SelectionCartePage(depart: _departPos, pointInitial: _destPos),
      ),
    );
    if (point != null && mounted) {
      setState(() {
        _destPos = point;
        _destinationCtrl.text = _texteCarte;
      });
    }
  }

  void _valider() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      Course(
        type: widget.type,
        depart: _departCtrl.text.trim(),
        destination: _destinationCtrl.text.trim(),
        prixEstime: _prix,
        date: DateTime.now(),
        departPos: _departPos,
        destinationPos: _destPos,
        distanceKm: _distanceKm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final km = _distanceKm;
    final lieuxAPlacer = [
      if (_departPos == null) 'le départ',
      if (_destPos == null) 'la destination',
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: couleurFond,
        title: Text(
          _estLivraison ? 'Nouvelle livraison' : 'Commander une moto',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Lieu de la commande'),
                      selected: !_autreLieuDepart,
                      onSelected: (_) => _choisirModeDepart(false),
                    ),
                    ChoiceChip(
                      label: const Text('Autre lieu'),
                      selected: _autreLieuDepart,
                      onSelected: (_) => _choisirModeDepart(true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _departCtrl,
                  readOnly: !_autreLieuDepart,
                  onChanged: (_) {
                    if (_departPos != null) {
                      setState(() => _departPos = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: _autreLieuDepart
                        ? 'Autre lieu de départ'
                        : 'Lieu de la commande',
                    prefixIcon: const Icon(
                      Icons.my_location,
                      color: couleurOrange,
                    ),
                    suffixIcon: _localisationEnCours
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: _autreLieuDepart
                                ? 'Choisir sur la carte'
                                : 'Actualiser ma position',
                            icon: Icon(
                              _autreLieuDepart
                                  ? Icons.map_outlined
                                  : Icons.gps_fixed,
                            ),
                            onPressed: _autreLieuDepart
                                ? _choisirDepartSurCarte
                                : _utiliserMaPosition,
                          ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Indiquez le point de départ'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _destinationCtrl,
                  onChanged: (_) => setState(() => _destPos = null),
                  decoration: InputDecoration(
                    labelText: 'Destination',
                    prefixIcon: const Icon(
                      Icons.location_on,
                      color: couleurOrange,
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Choisir sur la carte',
                      icon: const Icon(Icons.map_outlined),
                      onPressed: _choisirSurCarte,
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Indiquez la destination'
                      : null,
                ),
                if (_estLivraison) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description du colis (optionnel)',
                      prefixIcon: Icon(
                        Icons.inventory_2_outlined,
                        color: couleurOrange,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: couleurCarte,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      if (km != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Distance',
                              style: TextStyle(color: Colors.white70),
                            ),
                            Text(
                              '${km.toStringAsFixed(1)} km',
                              style: const TextStyle(color: couleurTexte),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            km != null ? 'Prix estimé' : 'Prix indicatif',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          Text(
                            '$_prix FCFA',
                            style: const TextStyle(
                              color: couleurOrange,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (km == null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Choisissez ${lieuxAPlacer.join(' et ')} sur la carte '
                          'pour calculer le prix selon la distance.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: couleurOrange,
                      foregroundColor: couleurFond,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _valider,
                    child: const Text(
                      'Confirmer la commande',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mes courses
// ---------------------------------------------------------------------------

class MesCoursesPage extends StatelessWidget {
  final List<Course> courses;
  const MesCoursesPage({super.key, required this.courses});

  String _heure(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: couleurFond,
        title: const Text('Mes courses'),
      ),
      body: courses.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 60,
                      color: Colors.white38,
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Aucune course pour le moment.\nCommandez votre première moto !',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, height: 1.5),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: courses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final c = courses[i];
                final livraison = c.type == TypeCourse.livraison;
                return Card(
                  color: couleurCarte,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: CircleAvatar(
                      backgroundColor: couleurOrange.withValues(alpha: 0.15),
                      child: Icon(
                        livraison ? Icons.delivery_dining : Icons.motorcycle,
                        color: couleurOrange,
                      ),
                    ),
                    title: Text(
                      '${c.depart} → ${c.destination}',
                      style: const TextStyle(
                        color: couleurTexte,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${livraison ? 'Livraison' : 'Moto'} • ${_heure(c.date)}${c.distanceKm != null ? ' • ${c.distanceKm!.toStringAsFixed(1)} km' : ''}\n${c.statut}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ),
                    trailing: Text(
                      '${c.prixEstime} F',
                      style: const TextStyle(
                        color: couleurOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compte
// ---------------------------------------------------------------------------

class ComptePage extends StatelessWidget {
  final VoidCallback onDevenirMotard;
  const ComptePage({super.key, required this.onDevenirMotard});

  Future<void> _deconnecter(BuildContext context) async {
    try {
      await DatabaseService.client.auth.signOut();
    } on Exception catch (error) {
      if (context.mounted) {
        afficherMessage(context, messageErreurBaseDeDonnees(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = DatabaseService.isConfigured
        ? DatabaseService.client.auth.currentUser
        : null;
    return Scaffold(
      appBar: AppBar(backgroundColor: couleurFond, title: const Text('Compte')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: couleurCarte,
              child: Icon(Icons.person, size: 50, color: couleurOrange),
            ),
          ),
          const SizedBox(height: 14),
          const Center(
            child: Text(
              'Utilisateur Thiak-Thiak',
              style: TextStyle(
                color: couleurTexte,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'Compte connecté',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          Center(
            child: Text(
              user?.phone ?? 'Mode démo local',
              style: const TextStyle(color: couleurTexte),
            ),
          ),
          const SizedBox(height: 28),
          _LigneCompte(
            icone: Icons.two_wheeler,
            titre: 'Espace motard',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const EspaceMotardPage())),
          ),
          const SizedBox(height: 12),
          _LigneCompte(
            icone: Icons.directions_bike,
            titre: 'Devenir motard',
            onTap: onDevenirMotard,
          ),
          const SizedBox(height: 12),
          _LigneCompte(
            icone: Icons.admin_panel_settings_outlined,
            titre: 'Espace administrateur',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AdminEntryPage())),
          ),
          const SizedBox(height: 12),
          _LigneCompte(
            icone: Icons.help_outline,
            titre: 'Aide et support',
            onTap: () =>
                afficherMessage(context, 'Support bientôt disponible.'),
          ),
          const SizedBox(height: 12),
          _LigneCompte(
            icone: Icons.info_outline,
            titre: 'À propos',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Thiak-Thiak',
              applicationVersion: '0.1.0',
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 12),
            _LigneCompte(
              icone: Icons.logout,
              titre: 'Se déconnecter',
              onTap: () => _deconnecter(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _LigneCompte extends StatelessWidget {
  final IconData icone;
  final String titre;
  final VoidCallback onTap;

  const _LigneCompte({
    required this.icone,
    required this.titre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: couleurCarte,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icone, color: couleurOrange),
        title: Text(titre, style: const TextStyle(color: couleurTexte)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inscription motard
// ---------------------------------------------------------------------------

class InscriptionMotardPage extends StatefulWidget {
  const InscriptionMotardPage({super.key});

  @override
  State<InscriptionMotardPage> createState() => _InscriptionMotardPageState();
}

class _InscriptionMotardPageState extends State<InscriptionMotardPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _plaqueCtrl = TextEditingController();
  final _database = const DatabaseRepository();
  bool _envoi = false;

  @override
  void dispose() {
    _nomCtrl.dispose();
    _telCtrl.dispose();
    _plaqueCtrl.dispose();
    super.dispose();
  }

  String? _requis(String? v, String message) =>
      (v == null || v.trim().isEmpty) ? message : null;

  Future<void> _envoyer() async {
    if (!_formKey.currentState!.validate()) return;
    if (DatabaseService.isConfigured) {
      setState(() => _envoi = true);
      try {
        await _database.createMotoristApplication(
          name: _nomCtrl.text,
          phone: _telCtrl.text,
          plate: _plaqueCtrl.text,
        );
      } on Exception catch (error) {
        if (mounted) {
          setState(() => _envoi = false);
          afficherMessage(context, messageErreurBaseDeDonnees(error));
        }
        return;
      }
      if (mounted) setState(() => _envoi = false);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    afficherMessage(
      context,
      DatabaseService.isConfigured
          ? 'Demande enregistrée. Nous vous contacterons bientôt.'
          : 'Demande en mode démo : elle ne sera pas enregistrée en ligne.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: couleurFond,
        title: const Text('Devenir motard'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nomCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom complet',
                    prefixIcon: Icon(
                      Icons.person_outline,
                      color: couleurOrange,
                    ),
                  ),
                  validator: (v) => _requis(v, 'Indiquez votre nom'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _telCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone',
                    prefixIcon: Icon(
                      Icons.phone_outlined,
                      color: couleurOrange,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 9) {
                      return 'Numéro invalide';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _plaqueCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Plaque d’immatriculation',
                    prefixIcon: Icon(Icons.two_wheeler, color: couleurOrange),
                  ),
                  validator: (v) => _requis(v, 'Indiquez la plaque'),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: couleurOrange,
                      foregroundColor: couleurFond,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _envoi ? null : _envoyer,
                    child: Text(
                      _envoi ? 'Envoi...' : 'Envoyer ma demande',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets et utilitaires partagés
// ---------------------------------------------------------------------------

class BoutonService extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String description;
  final Color couleur;
  final VoidCallback onTap;

  const BoutonService({
    super.key,
    required this.icone,
    required this.titre,
    required this.description,
    required this.couleur,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: couleurCarte,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          radius: 27,
          backgroundColor: couleur.withValues(alpha: 0.15),
          child: Icon(icone, color: couleur, size: 30),
        ),
        title: Text(
          titre,
          style: const TextStyle(
            color: couleurTexte,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            description,
            style: const TextStyle(color: Colors.white60),
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 17),
        onTap: onTap,
      ),
    );
  }
}

void afficherMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
