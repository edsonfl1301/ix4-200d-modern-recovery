# ix4-200d Integrated Recovery — experimental 0.3

**Repositório de fontes e instruções de construção. Não inclui o firmware proprietário nem um ZIP pronto para restaurar.** Os arquivos binários necessários são obtidos ou gerados localmente pelo usuário.

Recovery USB baseado no **Cloud Edition 3.2.6.17887**, com Samba 4.18.11, nginx 1.26.3 e OpenSSL 3.0.22 integrados. Não é firmware oficial nem atualização para aplicar sobre o NAS em uso.

Esta versão reúne o recovery e as melhorias de manutenção em uma única instalação: SMB moderno com assinatura, HTTPS na porta padrão **443**, certificado exclusivo gerado no primeiro boot, sincronização de contas/pastas/permissões e supervisão com logs limitados. Não é necessário executar o complemento separado depois da restauração.

O HTTPS antigo permanece em `127.0.0.1:4443`. O Apache original fornece o painel por HTTP internamente. Após configurar o armazenamento e uma conta com senha no painel, os compartilhamentos são importados automaticamente para o Samba moderno. Nenhuma credencial ou certificado privado de uma instalação real faz parte do projeto.

O supervisor verifica o processo/porta SMB, o handshake TLS com certificado verificado e o backend HTTP. Ele não encerra automaticamente processos ativos por falha de saúde. Configurações de compartilhamentos instáveis, vazias ou inválidas são rejeitadas; a última versão válida é preservada. Atualizações são recarregadas nos processos Samba existentes.

A simulação da versão 0.3 usa SMB em 1447 e HTTPS em 8445 para não interferir nos serviços de produção. A instalação restaurada usa as portas padrão 445 e 443. O teste de integridade de 1 MiB negociou SMB 3.1.1 com assinatura obrigatória; HTTPS retornou HTTP 200 com certificado exclusivo verificado.

Os binários continuam nas versões já testadas. Isto não atualiza o kernel nem equivale a uma atualização completa de segurança da plataforma. O cliente de torrent original é preservado; transferência externa de dados não foi validada com sucesso. Nenhuma credencial do firewall é integrada e nenhuma liberação de rede é feita pelo recovery. Personalizações de conteúdo, como nome do NAS, usuários e pasta Videos, continuam sendo configuradas no painel; suas permissões passam automaticamente ao SMB moderno.

## ATENÇÃO: teste em discos separados

**Retire TODOS os discos do conjunto atual, identificando as posições, antes de usar este recovery. Use somente discos que podem ser apagados.** O pacote inclui o marcador `reinstall`, que solicita reinstalação completa ao instalador original.

O instalador original pode recriar partições e RAID e **regrava kernel/initrd na NAND interna**, mesmo que o objetivo seja instalar o sistema nos HDs. Mantivemos esses dois arquivos idênticos ao recovery original; isso não elimina o efeito da gravação. Não alteramos o U-Boot nem seu ambiente. Preserve o recovery original e o acesso serial que já funcionou no seu aparelho.

O teste com dois discos ainda não está certificado. O script original constrói RAID1 de sistema com quatro posições e admite membros ausentes, mas isso não prova o mínimo de discos aceito pelo fluxo inteiro. Quatro discos de teste são preferíveis para validar as quatro baias. O suporte a quatro HDs de 4 TB não foi testado por este projeto.

## O que está integrado

- A imagem `apps` contém o runtime genérico e os scripts em `/usr/local/iomega-modern`.
- A imagem `config` inicia o bootstrap por `/etc/rc.local` e habilita o backend HTTP na porta 80.
- O primeiro boot extrai o runtime para `/mnt/system/iomega-modern`, gera um certificado exclusivo e inicia a supervisão.
- O HTTPS adicional usa **443** e encaminha ao painel HTTP local. Não habilite o HTTPS antigo pelo painel.
- Depois de criar uma conta autenticada e o volume de dados, o SMB moderno usa **445**, SMB2 ou superior e assinatura obrigatória.
- Contas e ACLs de compartilhamentos são derivadas do sistema original, em vez de gravar a senha/IP do desenvolvedor na imagem.
- O Samba legado fica na porta 139. O sistema base antigo não foi substituído nem recebeu uma auditoria completa de segurança.
- O kernel, initrd e oem permanecem byte a byte iguais aos originais.

Não há atualização automática para 3.2.16.30221 neste pacote: a base de recovery é 3.2.6.17887. Uma atualização oficial posterior pode substituir as imagens personalizadas e remover as melhorias.

## Preparação do USB

1. Use um pendrive FAT32 vazio e copie o conteúdo da pasta **USB** para a raiz.
2. A estrutura final deve ser:

```text
USB:\emctools\ix4-200d_images\ix4-200d.tgz
USB:\emctools\ix4-200d_images\reinstall
```

3. Não misture outro `.tgz`, `noextraction` ou uma pasta `temp` antiga nesse diretório.
4. Com o NAS desligado e apenas os discos de teste instalados, conecte o USB e use o procedimento de recuperação que já funcionou nesse aparelho: ligar mantendo Reset pressionado até o reconhecimento do USB no visor/indicador; então soltar. Não interrompa a alimentação durante a gravação.
5. Aguarde o ciclo de recuperação concluir. O fluxo pode desligar o aparelho; retire o USB antes da próxima inicialização normal.
6. Acesse o IP mostrado no visor por **HTTP** e conclua a configuração original, criando uma conta com senha e os compartilhamentos.
7. O primeiro certificado RSA pode levar alguns minutos para ser gerado. Teste `https://IP`; o certificado autossinado precisa de confiança no computador.
8. Teste `\\IP\NomeDoCompartilhamento` com a conta criada. Não reative SMB1 no Windows para validar este projeto.

O arquivo `reinstall` pode ser removido pelo próprio instalador. Para repetir uma instalação limpa, recrie o marcador a partir do pacote original; nunca faça isso com o conjunto atual conectado.

## Validação pendente / critérios de aceite

A rotina genérica 0.3 de primeiro boot foi executada em uma pasta isolada no NAS atual, com portas 1447/8445: gerou certificado distinto, negociou SMB 3.1.1 com assinatura obrigatória usando um cliente de teste no Windows, passou em leitura/escrita de 1 MiB com SHA-256 e retornou HTTP 200 em HTTPS com certificado validado. Uma origem de compartilhamentos inválida retornou erro 2 sem modificar o hash da configuração ativa. Os mapeamentos Windows de produção não foram desconectados. A instância de teste foi encerrada e seus mounts foram desmontados. Isso não substitui uma instalação em HDs vazios com a base 3.2.6.

A instalação completa em discos vazios ainda precisa ser testada fisicamente. Antes de considerar a versão aprovada:

- O recovery deve concluir sem erro de checksum, extração, partição ou gravação.
- O painel deve reconhecer a capacidade correta de todos os discos e criar o armazenamento.
- O supervisor deve iniciar SMB e HTTPS, com certificado exclusivo e sem senha fixa do projeto.
- Windows deve negociar SMB2/3 com assinatura e permitir criar, ler, renomear e remover um arquivo de teste.
- Reinício normal deve preservar o armazenamento e trazer os serviços automaticamente.
- Devem ser conferidos temperaturas, ventoinha, desligamento, logs e estado do RAID.
- Reset de fábrica e atualização oficial posterior não foram validados com esta customização.
- Antes de recolocar o conjunto antigo, desligue e retire todos os discos de teste. A recuperação também altera NAND; o retorno ao conjunto antigo exige validação, não apenas presumir compatibilidade.

## Construção

O firmware original deve ser obtido legalmente pelo usuário. Este repositório não o fornece. Primeiro compile `legacy_socket_compat.so` com o comando Zig descrito abaixo; depois baixe o runtime e prepare o payload. Consulte [VALIDATION.md](VALIDATION.md) para o alcance dos testes.


Requisitos no Linux: Python 3.9+, `sh`, `tar`, `gzip`, `md5sum`, `sha256sum`, `debugfs`, `e2fsck`, `awk`, Zig 0.14.1. A construção trabalha somente em arquivos copiados; não monta nem grava um disco físico.

1. Obtenha o recovery original 3.2.6.17887. Execute `python fetch_runtime.py` para reconstruir o runtime dos pacotes oficiais pinados em `packages-manifest.json`. Esse processo verifica SHA-256 de cada pacote.
2. Prepare o payload:

```text
python prepare_payload.py --original /caminho/ix4-200d.tgz --runtime payload/runtime.tar.gz --shim payload/legacy_socket_compat.so --package-manifest packages-manifest.json
```

3. Construa em uma pasta vazia com o sufixo exigido:

```sh
sh build-on-linux.sh /caminho/ix4-200d.tgz "$PWD/payload" /caminho/ix4-integrated-output
```

4. Verifique o `.tgz` resultante com o leitor ext2 independente:

```text
python verify_recovery.py /caminho/ix4-integrated-output/ix4-200d.tgz --report verification.json
```

5. Opcionalmente, prepare um ZIP local com a estrutura do pendrive e o marcador de reinstalação:

```sh
python package_usb.py /caminho/ix4-integrated-output/ix4-200d.tgz --report verification.json --output dist/ix4-recovery-0.3-local.zip
```

O ZIP local contém um marcador `reinstall` destrutivo e não deve ser aplicado ao conjunto de discos em uso. A pasta `USB` só é gerada depois da construção local. Não publique o resultado sem revisar os direitos de redistribuição do firmware e as obrigações dos componentes de terceiros.

Os checksums MD5 de compatibilidade do instalador não são assinaturas criptográficas de origem. O relatório também fornece SHA-256 para identificar os artefatos produzidos.

A imagem original contém avisos de filesystem, incluindo links simbólicos vazios e ausência de `lost+found`. O construtor não executa reparo automático. Ele compara os diagnósticos completos antes/depois (exceto o contador final de blocos/inodes usados) e exige que nenhum aviso novo seja introduzido. Não se deve apresentar essa checagem como filesystem original sem avisos.

A biblioteca `legacy_socket_compat.so` pode ser compilada a partir de `legacy_socket_compat.c` com Zig 0.14.1:

```text
zig build-lib -target arm-linux-musleabi -mcpu=arm926ej_s -dynamic -fPIC -fno-compiler-rt -O ReleaseSmall -femit-bin=payload/legacy_socket_compat.so legacy_socket_compat.c
```

## Diagnóstico e desativação

Logs: `/tmp/iomega-integrated-boot.log` e `/mnt/system/iomega-modern/var/log/`.

O marcador `/mnt/system/iomega-modern/DISABLED` impede o início no boot e encerra o supervisor no próximo ciclo; não encerra instantaneamente os serviços já iniciados. Para uma reversão completa, pare apenas os PIDs cujos executáveis estejam dentro desse runtime, restaure a configuração Samba original e o `rc.local` do recovery original. Não use `killall smbd`, que atingiria as duas versões.

O SSH não é habilitado automaticamente por esta imagem. Se necessário para o diagnóstico, use o controle oficial em `diagnostics.html`.

## GitHub e distribuição

Este repositório público contém somente o construtor, os scripts e instruções. As imagens proprietárias do firmware original e os pacotes binários de recuperação não são distribuídos aqui. `.gitignore` exclui as imagens proprietárias, arquivos de entrada e artefatos gerados. A licença MIT cobre somente o código novo deste projeto; firmware Iomega, Samba, nginx, OpenSSL e bibliotecas têm licenças próprias. Antes de uma distribuição pública de binários, completar os avisos e a disponibilização dos fontes correspondentes dos componentes de terceiros. Não publicar backups privados, credenciais nem certificados privados.
