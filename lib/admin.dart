import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart'
    show couleurFond, couleurCarte, couleurOrange, couleurTexte, afficherMessage;

// ---------------------------------------------------------------------------
// Modèle
// ---------------------------------------------------------------------------

class Admin {
  final String id;
  final String nom;
  final String telephone;
  final String sel;
  final String empreinte; // hash du mot de passe (jamais le mot de passe)
  final bool superAdmin;
  final DateTime creeLe;

  const Admin({
    required this.id,
    required this.nom,
    required this.telephone,
    required this.sel,
    required this.empreinte,
    required this.superAdmin,
    required this.creeLe,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nom': nom,
        'telephone': telephone,
        'sel': sel,
        'empreinte': empreinte,
        'superAdmin': superAdmin,
        'creeLe': creeLe.toIso8601String(),
      };

  factory Admin.fromJson(Map<String, dynamic> j) => Admin(
        id: j['id'] as String,
        nom: j['nom'] as String,
        telephone: j['telephone'] as String,
        sel: j['sel'] as String,
        empreinte: j['empreinte'] as String,
        superAdmin: j['superAdmin'] as bool,
        creeLe: DateTime.parse(j['creeLe'] as String),
      );
}

// ---------------------------------------------------------------------------
// Service (stockage local sur l'appareil)
// ---------------------------------------------------------------------------

class AdminService extends ChangeNotifier {
  AdminService._();
  static final AdminService instance = AdminService._();

  static const _cle = 'thiak_admins_v2';

  final List<Admin> _admins = [];
  Admin? _courant;
  bool _charge = false;

  List<Admin> get admins => List.unmodifiable(_admins);
  Admin? get courant => _courant;
  bool get charge => _charge;
  bool get aucunAdmin => _admins.isEmpty;

  Future<void> charger() async {
    if (_charge) return;
    final prefs = await SharedPreferences.getInstance();
    final brut = prefs.getString(_cle);
    if (brut != null) {
      final liste = jsonDecode(brut) as List<dynamic>;
      _admins
        ..clear()
        ..addAll(
          liste.map((e) => Admin.fromJson(e as Map<String, dynamic>)),
        );
    }
    _charge = true;
    notifyListeners();
  }

  Future<void> _sauvegarder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cle,
      jsonEncode(_admins.map((a) => a.toJson()).toList()),
    );
  }

  String _genererSel() {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  String _hasher(String motDePasse, String sel) =>
      sha256.convert(utf8.encode('$sel:$motDePasse')).toString();

  /// Crée un administrateur. Retourne un message d'erreur, ou null si succès.
  /// Le tout premier administrateur créé devient super administrateur
  /// et est connecté automatiquement.
  Future<String?> creer({
    required String nom,
    required String telephone,
    required String motDePasse,
  }) async {
    final tel = normaliserTelephone(telephone);
    if (_admins.any((a) => a.telephone == tel)) {
      return 'Un administrateur avec ce numéro existe déjà.';
    }
    final premier = _admins.isEmpty;
    final sel = _genererSel();
    final admin = Admin(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      nom: nom.trim(),
      telephone: tel,
      sel: sel,
      empreinte: _hasher(motDePasse, sel),
      superAdmin: premier,
      creeLe: DateTime.now(),
    );
    _admins.add(admin);
    await _sauvegarder();
    if (premier) _courant = admin;
    notifyListeners();
    return null;
  }

  bool connecter(String telephone, String motDePasse) {
    final tel = normaliserTelephone(telephone);
    for (final a in _admins) {
      if (a.telephone == tel && a.empreinte == _hasher(motDePasse, a.sel)) {
        _courant = a;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  void deconnecter() {
    _courant = null;
    notifyListeners();
  }

  /// Seul le super administrateur peut supprimer, et jamais lui-même.
  Future<String?> supprimer(String id) async {
    if (_courant == null || !_courant!.superAdmin) {
      return 'Action réservée au super administrateur.';
    }
    if (_courant!.id == id) {
      return 'Vous ne pouvez pas supprimer votre propre compte.';
    }
    _admins.removeWhere((a) => a.id == id);
    await _sauvegarder();
    notifyListeners();
    return null;
  }
}

// ---------------------------------------------------------------------------
// Point d'entrée : choisit la bonne page selon l'état
// ---------------------------------------------------------------------------

class AdminEntryPage extends StatefulWidget {
  const AdminEntryPage({super.key});

  @override
  State<AdminEntryPage> createState() => _AdminEntryPageState();
}

class _AdminEntryPageState extends State<AdminEntryPage> {
  final _service = AdminService.instance;

  @override
  void initState() {
    super.initState();
    _service.charger();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        if (!_service.charge) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (_service.aucunAdmin) {
          return const CreationAdminPage(premier: true);
        }
        if (_service.courant == null) {
          return const ConnexionAdminPage();
        }
        return const TableauAdminPage();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Champ mot de passe réutilisable
// ---------------------------------------------------------------------------

class _ChampMotDePasse extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  const _ChampMotDePasse({
    required this.controller,
    required this.label,
    this.validator,
  });

  @override
  State<_ChampMotDePasse> createState() => _ChampMotDePasseState();
}

class _ChampMotDePasseState extends State<_ChampMotDePasse> {
  bool _cache = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _cache,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline, color: couleurOrange),
        suffixIcon: IconButton(
          icon: Icon(_cache ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _cache = !_cache),
        ),
      ),
    );
  }
}

/// Retire espaces, tirets et indicatif (+221 ou 00221) : ne garde que
/// les 9 chiffres du numéro local.
String normaliserTelephone(String saisie) {
  var t = saisie.replaceAll(RegExp(r'[\s\-\.\(\)]'), '');
  if (t.startsWith('+221')) {
    t = t.substring(4);
  } else if (t.startsWith('00221')) {
    t = t.substring(5);
  }
  return t;
}

// Numéros mobiles sénégalais : 70, 75, 76, 77 ou 78 suivis de 7 chiffres.
final _regexTelSenegal = RegExp(r'^7[05678][0-9]{7}$');

bool telephoneValide(String saisie) =>
    _regexTelSenegal.hasMatch(normaliserTelephone(saisie));

String formaterTelephone(String t) => t.length == 9
    ? '+221 ${t.substring(0, 2)} ${t.substring(2, 5)} ${t.substring(5, 7)} ${t.substring(7)}'
    : t;

ButtonStyle _styleBouton() => FilledButton.styleFrom(
      backgroundColor: couleurOrange,
      foregroundColor: couleurFond,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

// ---------------------------------------------------------------------------
// Connexion
// ---------------------------------------------------------------------------

class ConnexionAdminPage extends StatefulWidget {
  const ConnexionAdminPage({super.key});

  @override
  State<ConnexionAdminPage> createState() => _ConnexionAdminPageState();
}

class _ConnexionAdminPageState extends State<ConnexionAdminPage> {
  final _formKey = GlobalKey<FormState>();
  final _telCtrl = TextEditingController();
  final _mdpCtrl = TextEditingController();

  @override
  void dispose() {
    _telCtrl.dispose();
    _mdpCtrl.dispose();
    super.dispose();
  }

  void _connexion() {
    if (!_formKey.currentState!.validate()) return;
    final ok =
        AdminService.instance.connecter(_telCtrl.text, _mdpCtrl.text);
    if (!ok) afficherMessage(context, 'Numéro ou mot de passe incorrect.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: couleurFond,
        title: const Text('Espace administrateur'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Icon(Icons.admin_panel_settings,
                    size: 70, color: couleurOrange),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _telCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Numéro de téléphone',
                    hintText: '77 123 45 67',
                    prefixText: '+221 ',
                    prefixIcon: Icon(Icons.phone_outlined, color: couleurOrange),
                  ),
                  validator: (v) => (v == null || !telephoneValide(v))
                      ? 'Numéro invalide (ex : 77 123 45 67)'
                      : null,
                ),
                const SizedBox(height: 16),
                _ChampMotDePasse(
                  controller: _mdpCtrl,
                  label: 'Mot de passe',
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Saisissez le mot de passe' : null,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: _styleBouton(),
                    onPressed: _connexion,
                    child: const Text(
                      'Se connecter',
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
// Formulaire de création d'un administrateur
// (sert aussi à créer le tout premier compte)
// ---------------------------------------------------------------------------

class CreationAdminPage extends StatefulWidget {
  final bool premier;
  const CreationAdminPage({super.key, this.premier = false});

  @override
  State<CreationAdminPage> createState() => _CreationAdminPageState();
}

class _CreationAdminPageState extends State<CreationAdminPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _mdpCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _envoi = false;

  @override
  void dispose() {
    _nomCtrl.dispose();
    _telCtrl.dispose();
    _mdpCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _envoi = true);
    final erreur = await AdminService.instance.creer(
      nom: _nomCtrl.text,
      telephone: _telCtrl.text,
      motDePasse: _mdpCtrl.text,
    );
    if (!mounted) return;
    setState(() => _envoi = false);

    if (erreur != null) {
      afficherMessage(context, erreur);
      return;
    }
    if (!widget.premier) {
      Navigator.of(context).pop();
      afficherMessage(context, 'Administrateur créé avec succès.');
    }
    // Pour le premier admin, AdminEntryPage bascule seule vers le tableau.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: couleurFond,
        title: Text(widget.premier
            ? 'Créer le premier administrateur'
            : 'Nouvel administrateur'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                if (widget.premier)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: couleurCarte,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Aucun administrateur n’existe encore. Ce premier compte '
                      'sera le super administrateur et pourra en créer d’autres.',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                  ),
                TextFormField(
                  controller: _nomCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nom complet',
                    prefixIcon: Icon(Icons.person_outline, color: couleurOrange),
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Indiquez le nom'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _telCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Numéro de téléphone',
                    hintText: '77 123 45 67',
                    prefixText: '+221 ',
                    prefixIcon: Icon(Icons.phone_outlined, color: couleurOrange),
                  ),
                  validator: (v) => (v == null || !telephoneValide(v))
                      ? 'Numéro invalide (ex : 77 123 45 67)'
                      : null,
                ),
                const SizedBox(height: 16),
                _ChampMotDePasse(
                  controller: _mdpCtrl,
                  label: 'Mot de passe (8 caractères minimum)',
                  validator: (v) => (v == null || v.length < 8)
                      ? 'Au moins 8 caractères'
                      : null,
                ),
                const SizedBox(height: 16),
                _ChampMotDePasse(
                  controller: _confirmCtrl,
                  label: 'Confirmer le mot de passe',
                  validator: (v) =>
                      v != _mdpCtrl.text ? 'Les mots de passe diffèrent' : null,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: _styleBouton(),
                    onPressed: _envoi ? null : _creer,
                    child: _envoi
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Créer le compte',
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
// Tableau de bord administrateur
// ---------------------------------------------------------------------------

class TableauAdminPage extends StatelessWidget {
  const TableauAdminPage({super.key});

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _supprimer(BuildContext context, Admin a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet administrateur ?'),
        content: Text('${a.nom} (${formaterTelephone(a.telephone)}) n’aura plus accès à cet espace.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final erreur = await AdminService.instance.supprimer(a.id);
    if (context.mounted && erreur != null) afficherMessage(context, erreur);
  }

  @override
  Widget build(BuildContext context) {
    final s = AdminService.instance;

    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
    final moi = s.courant;
    if (moi == null) return const SizedBox.shrink();
    final admins = s.admins;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: couleurFond,
        title: const Text('Espace administrateur'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: s.deconnecter,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: couleurOrange,
        foregroundColor: couleurFond,
        icon: const Icon(Icons.person_add),
        label: const Text('Nouvel administrateur'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreationAdminPage()),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: couleurCarte,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: couleurOrange.withValues(alpha: 0.15),
                  child: const Icon(Icons.admin_panel_settings,
                      color: couleurOrange, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        moi.nom,
                        style: const TextStyle(
                          color: couleurTexte,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        moi.superAdmin
                            ? 'Super administrateur'
                            : 'Administrateur',
                        style: const TextStyle(color: couleurOrange),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Administrateurs (${admins.length})',
            style: const TextStyle(
              color: couleurTexte,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          for (final a in admins) ...[
            Card(
              color: couleurCarte,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: Icon(
                  a.superAdmin ? Icons.shield : Icons.person_outline,
                  color: couleurOrange,
                ),
                title: Text(a.nom,
                    style: const TextStyle(color: couleurTexte)),
                subtitle: Text(
                  '${formaterTelephone(a.telephone)}\nCréé le ${_date(a.creeLe)}',
                  style: const TextStyle(color: Colors.white60),
                ),
                isThreeLine: true,
                trailing: (moi.superAdmin && a.id != moi.id)
                    ? IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent),
                        onPressed: () => _supprimer(context, a),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
      },
    );
  }
}